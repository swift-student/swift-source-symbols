/** Outside */
@Mark("{ fun fake() {} }")
public class Host(val callback: () -> Unit = { println("}") }) /* before body */ {
    // Not a declaration: fun fake() {}
    suspend fun <T> work(
        value: List</* inside */ T?>,
        callback: () -> Unit = { println("{") },
    ): T? where T : Any /* before body */ {
        return null
    } // after callable
    val stored = { "fun fake() {}" }
    val delegated by lazy { 1 }
    val computed: Int /* before getter */
        get() = 1
    typealias Alias = Map<String, Int>
}
