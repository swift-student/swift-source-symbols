package cases

fun outer(input: Int) {
    when (val `café` = run {
        fun helper() = input
        helper()
    }) {
        else -> {
            val branch = `café`
        }
    }
    when (val `café` = 2) {
        else -> println(`café`)
    }
    when (input) {
        else -> println(input)
    }
    for (loop in listOf(input)) {
        println(loop)
    }
    try { input } catch (caught: Exception) { println(caught) }
    listOf(input).map { lambda -> lambda }
}
val stored = when (val local = 1) {
    else -> local
}
class Container {
    val stored = when (val memberSubject = 1) {
        else -> memberSubject
    }
}
