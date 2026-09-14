package demo.`when`

fun outer(value: Int) {
    if (value > 0) {
        fun local() = value
    }
    run {
        fun local() = value
    }
    class Inner {
        fun member() {
            val nested = 1
        }
    }
    val owned = run {
        fun helper() = 1
        helper()
    }
    val (left, right) = run {
        fun shared() = 1
        pair()
    }
}
val service = object {
    fun work() {
        val local = 1
    }
}
class Host {
    companion object Factory {
        fun make() = 1
    }
    var value: Int = 0
        set(newValue) {
            val adjusted = newValue
            field = adjusted
        }
    fun String.extension() {
        fun nested() = this
    }
}
