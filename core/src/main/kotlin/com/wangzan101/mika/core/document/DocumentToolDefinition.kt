package com.wangzan101.mika.core.document

import com.wangzan101.mika.core.tool.ToolDef
import com.wangzan101.mika.core.tool.str
import com.wangzan101.mika.core.tool.strArray
import com.wangzan101.mika.core.tool.int
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Single document tool schema. Channel adapters supply their own delivery instruction. */
internal fun documentToolDefinition(deliveryHint: String): ToolDef = ToolDef("create_document",
        "Generate a local HTML, PDF or CSV document from known source content. Never invent missing source content; ask when source or table selection is ambiguous. document contains title and sections: heading(text, level 1-6), paragraph(text), bulletList/orderedList(items: string[]), table(columns: string[], rows: string[][]). Text is literal, not markup. Max 250000 characters, 200 sections, 12 columns and 1000 rows per table. CSV exports one table, with formula protection (apostrophe prefix); disclose this to the user. $deliveryHint",
        mapOf(
            "format" to buildJsonObject { put("type", "string"); put("enum", JsonArray(listOf("html", "pdf", "csv").map(::JsonPrimitive))) },
            "document" to buildJsonObject {
                put("type", "object")
                put("properties", buildJsonObject {
                    put("title", str("Document title, 1-200 characters."))
                    put("sections", buildJsonObject {
                        put("type", "array"); put("minItems", 1); put("maxItems", 200)
                        put("items", buildJsonObject {
                            put("type", "object")
                            put("properties", buildJsonObject {
                                put("type", str("Section type", listOf("heading", "paragraph", "bulletList", "orderedList", "table")))
                                put("text", str("Literal heading or paragraph text"))
                                put("level", int("Heading level", 1, 6))
                                put("items", strArray("List items", 1000))
                                put("columns", strArray("Table column labels", 12))
                                put("rows", buildJsonObject {
                                    put("type", "array"); put("maxItems", 1000)
                                    put("items", strArray("Row cells, including empty strings", 12))
                                })
                            })
                            put("required", JsonArray(listOf(JsonPrimitive("type"))))
                            put("additionalProperties", false)
                        })
                    })
                })
                put("required", JsonArray(listOf("title", "sections").map(::JsonPrimitive)))
                put("additionalProperties", false)
            },
            "tableIndex" to int("CSV only: zero-based index among table sections; required when multiple tables exist.", 0, 199),
        ), listOf("format", "document"))
