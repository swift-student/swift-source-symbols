@file:JvmName("Syntax")
package syntax
import other.Renamed as Alias

annotation class Mark(val value: String)
value class Identifier(val raw: String)
sealed interface Shape
fun interface Action {
    fun invoke()
}
enum class Mode(val code: Int) {
    FIRST(1) {
        override fun label() = "first"
    },
    SECOND(2);
    open fun label() = "second"
}
object Registry {
    const val ID = "fun imaginary() {}"
    val multiline = """
        class Imaginary
        fun imaginary() {}
    """
    /* outer /* inner fun imaginary() {} */ still comment */
    operator fun get(index: Int): String = ID
    infix fun accepts(other: Registry): Boolean = true
}
fun defaults(callback: () -> Int = { fun nested() = 1; nested() }) = callback()
fun repeat(value: Int) = value
fun repeat(value: Int) = value
