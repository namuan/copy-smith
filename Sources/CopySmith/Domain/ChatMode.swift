import Foundation

struct ChatMode: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let promptPrefix: String

    func buildPrompt(for text: String) -> String {
        "\(promptPrefix)\n\n\(text)"
    }

    static let all: [ChatMode] = [
        ChatMode(
            id: "proofread",
            title: "Proofread",
            promptPrefix: "Proofread the text to ensure it uses appropriate grammar, vocabulary, wording, and punctuation. You should maintain the original tone of the text, without altering it to be more formal or less formal. Output ONLY the corrected text without any additional comments. Maintain the original text structure and writing style. Respond in the same language as the input (e.g., English US, French):"
        ),
        ChatMode(
            id: "concise",
            title: "Concise",
            promptPrefix: "You are a writing assistant. Rewrite the text provided by the user to be slightly more concise in tone, thus making it just a bit shorter. Do not change the text too much or be too reductive. Output ONLY the concise version without additional comments. Respond in the same language as the input (e.g., English US, French):"
        ),
        ChatMode(
            id: "professional",
            title: "Professional",
            promptPrefix: "You are a writing assistant. Rewrite the text provided by the user to sound more professional. Output ONLY the professional text without additional comments. Respond in the same language as the input (e.g., English US, French):"
        ),
        ChatMode(
            id: "friendly",
            title: "Friendly",
            promptPrefix: "You are a writing assistant. Rewrite the text provided by the user to be more friendly. Output ONLY the friendly text without additional comments. Respond in the same language as the input (e.g., English US, French):"
        ),
        ChatMode(
            id: "rewrite",
            title: "Rewrite",
            promptPrefix: "You are a writing assistant. Rewrite the text provided by the user to improve phrasing. Output ONLY the rewritten text without additional comments. Respond in the same language as the input (e.g., English US, French):"
        ),
        ChatMode(
            id: "summarise",
            title: "Summarise",
            promptPrefix: "Provide summary in bullet points for the following text:"
        ),
        ChatMode(
            id: "explain",
            title: "Explain",
            promptPrefix: "Can you explain the following:"
        ),
        ChatMode(
            id: "fallacy-finder",
            title: "Fallacy Finder",
            promptPrefix: "I want you to act as a fallacy finder. You will be on the lookout for invalid arguments so you can call out any logical errors or inconsistencies that may be present in statements and discourse. Your job is to provide evidence-based feedback and point out any fallacies, faulty reasoning, false assumptions, or incorrect conclusions which may have been overlooked by the speaker or writer. Text:"
        )
    ]

    static func buildRefinePrompt(blocks: [(mode: ChatMode, text: String)]) -> String {
        let body = blocks
            .map { "## \($0.mode.title)\n\($0.text)" }
            .joined(separator: "\n\n")
        return """
        Review all the following alternative sentences and create a single, concise response that combines the strongest elements from each alternative. Preserve the exact tone and intent of the original sentences. Your output should contain ONLY the final consolidated response, with no additional commentary, explanations, or meta-text. Respond in the same language as the input:

        \(body)
        """
    }
}
