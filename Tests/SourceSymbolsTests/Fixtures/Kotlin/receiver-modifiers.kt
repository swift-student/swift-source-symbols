package receivers

fun suspend /* receiver */ (() -> Unit).run() = 1
fun (() -> Unit).run() = 2
fun suspend (() -> Unit).run(value: Int) = value
fun @receiver:Mark /* receiver */ (String).annotated() = this
val suspend (() -> Unit).ready: Boolean get() = true
val (() -> Unit).ready: Boolean get() = false
