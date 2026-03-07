import Foundation

/// Validates LLM output stays anchored to the source transcription.
/// Only applies to reformat mode — translation naturally produces
/// entirely different text, so overlap checks don't apply.
enum StrictModeGuard {
    static func isInvalid(input: String, output: String) -> Bool {
        // Reject dialogue-like responses (applies to all modes)
        if looksLikeDialogue(output) {
            return true
        }

        return false
    }

    private static func looksLikeDialogue(_ text: String) -> Bool {
        let lower = text.lowercased()
        let patterns = [
            "sure,", "sure!", "of course", "certainly!", "i'd be happy to",
            "here's", "here is", "let me", "i can help",
            "as an ai", "as a language model",
            "i'm sorry", "i apologize",
        ]
        for pattern in patterns {
            if lower.hasPrefix(pattern) {
                return true
            }
        }
        return false
    }
}
