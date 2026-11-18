import SwiftUI

/// A finished reply that has a table or a fenced code block, laid out as
/// blocks like Android's chat: a table as a grid with its header and rule
/// lines, and code in its own box. Wide content scrolls sideways inside the
/// bubble. Replies without either stay one Text (see ChatView).
struct ChatReplyBlocksView: View {
    let blocks: [ChatReplyMarkdown.Block]
    let ink: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text):
                    Text(text).fixedSize(horizontal: false, vertical: true)
                case .code(let lines):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(verbatim: lines.joined(separator: "\n"))
                            .font(.system(size: 13.5, design: .monospaced))
                            .fixedSize(horizontal: true, vertical: true)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                    }
                    .background(ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                case .table(let header, let rows):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                            GridRow {
                                ForEach(header.indices, id: \.self) { column in
                                    cell(header[column], heading: true)
                                }
                            }
                            .background(ink.opacity(0.07))
                            ForEach(rows.indices, id: \.self) { row in
                                Divider().overlay(ink.opacity(0.2))
                                GridRow {
                                    ForEach(rows[row].indices, id: \.self) { column in
                                        cell(rows[row][column], heading: false)
                                    }
                                }
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ink.opacity(0.2), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func cell(_ text: AttributedString, heading: Bool) -> some View {
        Text(text)
            .font(.system(size: 14.5, weight: heading ? .semibold : .regular))
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 56, maxWidth: 240, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 7)
    }
}
