#if FEATURE_A
struct Choice { func a() {} }
#else
struct Choice { func b() {} }
#endif
struct Container {
#if FEATURE_A
    func selected() {}
#elseif FEATURE_B
    func selected(value: Int) {}
#else
    func fallback() {}
#endif
}
