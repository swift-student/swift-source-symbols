package shop

// Leading documentation is outside the declaration.
data class Cart<T>(val item: T, private var count: Int = 0) where T : Any {
    constructor(item: T) : this(item, 1) {
        val ready = true
    }
    init {
        val checked = item
    }
    fun add(value: Int) {
        fun local() = value
    }
    fun add(value: String) = value
    val total: Int
        get() {
            val cached = count
            return cached
        }
    companion object {
        fun create() = 1
    }
    object Named {
        val version = 1
    }
}
interface Reader {
    fun read(): String
}
enum class State {
    OPEN,
    CLOSED;
    fun isOpen() = this == OPEN
}
typealias Callback<T> = (T) -> Unit
val top = 1
fun run() {
    val (first, _, second) = triple()
}
