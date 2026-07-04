import Testing

@main
struct PeekyTestMain {
    static func main() async {
        await Testing.__swiftPMEntryPoint() as Never
    }
}
