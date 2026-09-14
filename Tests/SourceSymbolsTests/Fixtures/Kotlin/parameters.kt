package sample

@Deprecated("old")
public suspend fun <T> List<T>.choose(
    value: T,
    vararg others: T,
    noinline callback: (T) -> Unit = { println(it) },
    `when`: Map<String, List<T?>> = emptyMap(),
): T? where T : Any = firstOrNull()
fun String.render(value: Int): String = this
fun Int.render(value: Int): String = toString()
fun plain() = 1
class Empty()
class Implicit
class WithDefaults private constructor(val title: String = "", vararg flags: Int)
val String.size: Int get() = length
