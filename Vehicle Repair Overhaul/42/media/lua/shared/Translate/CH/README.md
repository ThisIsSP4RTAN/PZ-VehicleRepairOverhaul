# The following content is copied from the Project Zomboid official GitHub version Build 41 translation repository for reference only. (September 23, 2025)

> Rule 1 has tested in Build 42, it can show a full symbol. May be there has has change later. (September 23, 2025)

## IMPORTANT GUIDELINES TO FOLLOW

THE GUIDELINES WRITTEN HERE ARE FOR TRADITIONAL CHINESE (CH) TRANSLATIONS, IF YOU'RE CONTRIBUTING TRANSLATIONS OF OTHER LANGUAGES, PLEASE REFER TO THEIR OWN SPECIFIC GUIDELINES.

### 1. Make sure you are **NOT** using any full-form symbols

The font **DOES NOT** support them as of build 41, and I don't expect it to work anytime soon.

Instead of:

> `你好，我（就是我！）是一個句子。`

You should enter:

> `你好, 我 (就是我! ) 是一個句子. `

### 2. If you're using TranslationZed, keep the following quirks in mind

- Since we changed CH encoding from Big5 to UTF-8, TranslationZed no longer works with CH translation.

But here are some previously found quirks:

- It does **NOT** support Recorded_Media.
- It fails to recognize keywords containing "=" correctly.
- It fails to recognize multi-line keywords correctly (You'll see the keyword ending with ".." instead of properly showing the next line).
