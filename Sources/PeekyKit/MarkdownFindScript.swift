import Foundation

/// Markdown 页面里 ⌘F 查找的页面端：注入 WKWebView，挂在 `window.peekyFind` 上。
///
/// 匹配在 Swift 里算（`TextSearch`），页面端只做两件事：
/// 1. `prepare` 把页面上看得见的文字按文档顺序拼成一份全文交给 Swift，同时记下每个文字节点
///    在全文里的起点；不同块（段落、列表项、单元格……）之间插一个换行，免得两段首尾粘成一个词。
///    `display:none` 的文字（例如 Mermaid 图画好后藏起来的源码）不算在内。
/// 2. `show` / `setCurrent` / `clear` 把 Swift 给回的 UTF-16 区间换回页面里的 DOM Range，
///    用 CSS Custom Highlight 画「全部匹配」和「当前匹配」两层，把当前匹配滚进视野，关闭时把它选中。
///
/// 页面 DOM 变了（Mermaid 随明暗重画）就标脏，下一次 `prepare` 重拼全文。
enum MarkdownFindScript {
    static let source = #"""
    (function() {
        if (window.peekyFind) { return; }

        var BLOCK_TAGS = new Set(['ADDRESS', 'ARTICLE', 'ASIDE', 'BLOCKQUOTE', 'BODY', 'CAPTION', 'DD', 'DETAILS',
            'DIV', 'DL', 'DT', 'FIGCAPTION', 'FIGURE', 'FOOTER', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'HEADER',
            'HR', 'LI', 'MAIN', 'NAV', 'OL', 'P', 'PRE', 'SECTION', 'SUMMARY', 'TABLE', 'TBODY', 'TD', 'TFOOT',
            'TH', 'THEAD', 'TR', 'UL']);
        var SKIP_TAGS = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE']);
        var supportsHighlight = !!(window.CSS && CSS.highlights && window.Highlight);

        var nodes = [];
        var corpusLength = 0;
        var isDirty = true;
        var ranges = [];
        var current = -1;

        var style = document.createElement('style');
        style.textContent = __PEEKY_FIND_CSS__;
        (document.head || document.documentElement).appendChild(style);

        new MutationObserver(function() { isDirty = true; })
            .observe(document.documentElement, { childList: true, subtree: true, characterData: true });

        function isRendered(element, cache) {
            var known = cache.get(element);
            if (known !== undefined) { return known; }
            var rendered = element.getClientRects().length > 0;
            cache.set(element, rendered);
            return rendered;
        }

        function blockOf(element, cache) {
            var start = element;
            var known = cache.get(start);
            if (known !== undefined) { return known; }
            while (element && !BLOCK_TAGS.has(element.tagName)) { element = element.parentElement; }
            var block = element || document.body;
            cache.set(start, block);
            return block;
        }

        function buildCorpus() {
            nodes = [];
            var parts = [];
            var length = 0;
            var lastBlock = null;
            var renderedCache = new Map();
            var blockCache = new Map();
            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
            while (walker.nextNode()) {
                var node = walker.currentNode;
                var parent = node.parentElement;
                if (!parent || SKIP_TAGS.has(parent.tagName)) { continue; }
                if (!node.data.trim() && !parent.closest('pre')) { continue; }
                if (!isRendered(parent, renderedCache)) { continue; }
                var block = blockOf(parent, blockCache);
                if (lastBlock !== null && block !== lastBlock) {
                    parts.push('\n');
                    length += 1;
                }
                lastBlock = block;
                nodes.push({ node: node, start: length });
                parts.push(node.data);
                length += node.data.length;
            }
            corpusLength = length;
            isDirty = false;
            return parts.join('');
        }

        function nodeBottom(index) {
            var range = document.createRange();
            range.selectNodeContents(nodes[index].node);
            return range.getBoundingClientRect().bottom;
        }

        // 视野顶端第一段文字在全文里的起点：文字节点按文档顺序排，纵向位置单调，二分即可。
        function viewportAnchor() {
            var low = 0;
            var high = nodes.length;
            while (low < high) {
                var mid = (low + high) >> 1;
                if (nodeBottom(mid) > 0) { high = mid; } else { low = mid + 1; }
            }
            return low < nodes.length ? nodes[low].start : corpusLength;
        }

        function selectionAnchor() {
            var selection = window.getSelection();
            if (!selection || selection.rangeCount === 0 || selection.isCollapsed) { return null; }
            var range = selection.getRangeAt(0);
            for (var i = 0; i < nodes.length; i++) {
                if (nodes[i].node === range.startContainer) { return nodes[i].start + range.startOffset; }
            }
            return null;
        }

        // 全文下标落在哪个文字节点：起点不大于它的最后一个。
        function locate(offset) {
            var low = 0;
            var high = nodes.length - 1;
            while (low < high) {
                var mid = (low + high + 1) >> 1;
                if (nodes[mid].start <= offset) { low = mid; } else { high = mid - 1; }
            }
            return nodes[low];
        }

        function makeRange(location, length) {
            var first = locate(location);
            var last = locate(Math.max(location, location + length - 1));
            var range = document.createRange();
            range.setStart(first.node, Math.min(location - first.start, first.node.length));
            range.setEnd(last.node, Math.min(location + length - last.start, last.node.length));
            return range;
        }

        function paint() {
            if (!supportsHighlight) {
                var selection = window.getSelection();
                selection.removeAllRanges();
                if (ranges[current]) { selection.addRange(ranges[current]); }
                return;
            }
            var all = new Highlight();
            for (var i = 0; i < ranges.length; i++) { all.add(ranges[i]); }
            var focused = new Highlight();
            if (ranges[current]) { focused.add(ranges[current]); }
            focused.priority = 1;
            CSS.highlights.set('peeky-find', all);
            CSS.highlights.set('peeky-find-current', focused);
        }

        // 当前匹配不在视野里才滚：横向先把它所在的可横滚块（代码块、宽表格）滚到位，
        // 纵向再把它放到视野上三分之一处。
        function reveal() {
            var range = ranges[current];
            if (!range) { return; }
            var element = range.startContainer.parentElement;
            while (element && element !== document.body && element !== document.documentElement) {
                if (element.scrollWidth > element.clientWidth + 1) {
                    var box = element.getBoundingClientRect();
                    var target = range.getBoundingClientRect();
                    if (target.left < box.left || target.right > box.right) {
                        element.scrollLeft += target.left - box.left - box.width / 3;
                    }
                }
                element = element.parentElement;
            }
            var rect = range.getBoundingClientRect();
            var margin = 48;
            if (rect.top < margin || rect.bottom > window.innerHeight - margin) {
                window.scrollTo(window.scrollX, window.scrollY + rect.top - window.innerHeight / 3);
            }
        }

        function isInViewport(range) {
            if (!range) { return false; }
            var rect = range.getBoundingClientRect();
            return rect.height > 0 && rect.top >= 0 && rect.bottom <= window.innerHeight;
        }

        window.peekyFind = {
            // haveCorpus：Swift 手里已有这一页的全文。没有、或页面变过，就重拼并交回。
            // preferSelection：起点优先取选区（⌘E 用选中文字查找时从选区处开始）。
            prepare: function(haveCorpus, preferSelection) {
                var corpus = null;
                if (!haveCorpus || isDirty) { corpus = buildCorpus(); }
                var anchor = preferSelection ? selectionAnchor() : null;
                if (anchor === null) { anchor = viewportAnchor(); }
                return { corpus: corpus, anchor: anchor };
            },
            // flat：[起点, 长度, 起点, 长度, …]（UTF-16）。返回当前匹配此刻是否在视野里。
            show: function(flat, index, shouldReveal) {
                ranges = [];
                for (var i = 0; i + 1 < flat.length; i += 2) { ranges.push(makeRange(flat[i], flat[i + 1])); }
                current = index;
                paint();
                if (shouldReveal) { reveal(); }
                return isInViewport(ranges[current]);
            },
            setCurrent: function(index, shouldReveal) {
                current = index;
                paint();
                if (shouldReveal) { reveal(); }
            },
            selectedText: function() {
                var selection = window.getSelection();
                return selection ? selection.toString() : '';
            },
            // 收起查找栏：去掉高亮；selectCurrent 时把当前匹配留成选中文字。
            clear: function(selectCurrent) {
                var range = ranges[current];
                if (supportsHighlight) {
                    CSS.highlights.delete('peeky-find');
                    CSS.highlights.delete('peeky-find-current');
                }
                if (selectCurrent && range) {
                    var selection = window.getSelection();
                    selection.removeAllRanges();
                    selection.addRange(range);
                }
                ranges = [];
                current = -1;
            }
        };
    })();
    """#

    /// 两层高亮的颜色：跟随页面的 prefers-color-scheme，与 github-markdown-css 的明暗同步。
    /// 全部匹配 = 黄、当前匹配 = 橙，色相与明度两处都不同；都避开选区色，收起查找栏时当前匹配
    /// 变成选区，这一下颜色变化本身就说明「查找结束、这段被选中了」。字色统一成正文色（链接蓝落在
    /// 深色琥珀底上对比度不够）。深色两层取 GitHub Primer 的 attention.muted 与 orange-3，
    /// 与 github-markdown-css 同源；深色下当前匹配是亮底深字、全部匹配是暗底浅字，正好反过来。
    static let highlightCSS = """
    ::highlight(peeky-find){background-color:rgba(255,204,0,0.50);color:#1f2328}
    ::highlight(peeky-find-current){background-color:#ffaa66;color:#1f2328}
    @media (prefers-color-scheme: dark){
    ::highlight(peeky-find){background-color:rgba(187,128,9,0.40);color:#f0f6fc}
    ::highlight(peeky-find-current){background-color:#f0883e;color:#0d1117}
    }
    """

    /// 注入页面的完整脚本：CSS 以 JS 字符串字面量嵌进去。
    static var userScriptSource: String {
        let cssLiteral = (try? JSONSerialization.data(withJSONObject: [highlightCSS], options: []))
            .flatMap { String(data: $0, encoding: .utf8) }
            .map { String($0.dropFirst().dropLast()) } ?? "''"
        return source.replacingOccurrences(of: "__PEEKY_FIND_CSS__", with: cssLiteral)
    }
}
