package com.getbux.assignment

import io.ktor.application.Application
import io.ktor.application.call
import io.ktor.html.respondHtml
import io.ktor.routing.get
import io.ktor.routing.routing
import kotlinx.html.a
import kotlinx.html.body
import kotlinx.html.h1
import kotlinx.html.head
import kotlinx.html.li
import kotlinx.html.title
import kotlinx.html.ul
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter


fun main(args: Array<String>): Unit = io.ktor.server.cio.EngineMain.main(args)

@Suppress("unused") // Referenced in application.conf
@kotlin.jvm.JvmOverloads
fun Application.module(testing: Boolean = false) {
    routing {
        get("/") {
            call.respondHtml {
                head {
                    title { +"What time is it?" }
                }
                body {
                    ul {
                        li {
                            a(href = "amsterdam") { +"Amsterdam" }
                        }
                        li {
                            a(href = "london") { +"London" }
                        }
                    }
                }
            }
        }

        get("/amsterdam") {
            call.respondHtml {
                head {
                    title { +"What time is it?" }
                }
                body {
                    h1 { +"It's ${currentTime("Europe/Amsterdam")} in Amsterdam"}
                }
            }
        }

        get("/london") {
            call.respondHtml {
                head {
                    title { +"What time is it?" }
                }
                body {
                    h1 { +"It's ${currentTime("Europe/London")} in London"}
                }
            }
        }
    }
}

fun currentTime(where: String): String {
    return Instant.now()
        .atZone(ZoneId.of(where))
        .format(DateTimeFormatter.ofPattern("HH:mm:ss"))
}
