/// Configuration written on first launch (same as `examples/pipe-to-underscore.json`).
/// With a Latin American Spanish layout, `|` types `_` and shift + `-` types `|`, while
/// shift + `|` keeps typing `°`.
enum DefaultConfig {
    static let json = """
    {
        "description": "| sin shift -> _ , - + shift -> |",
        "manipulators": [
            {
                "from": {
                    "key_code": "grave_accent_and_tilde",
                    "modifiers": { "mandatory": [] }
                },
                "to": [
                    {
                        "key_code": "slash",
                        "modifiers": ["shift"]
                    }
                ],
                "type": "basic"
            },
            {
                "from": {
                    "key_code": "slash",
                    "modifiers": { "mandatory": ["shift"] }
                },
                "to": [{ "key_code": "grave_accent_and_tilde" }],
                "type": "basic"
            }
        ]
    }

    """
}
