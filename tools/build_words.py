#!/usr/bin/env python3
# Rebuilds Letter Pyramid's word data from boggle.koplugin's dictionaries.
# Run from the monorepo root:
#
#   python3 letterpyramid.koplugin/tools/build_words.py EN_FREQ FR_FREQ
#
# where EN_FREQ / FR_FREQ are the OpenSubtitles frequency lists en_50k.txt and
# fr_50k.txt from https://github.com/hermitdave/FrequencyWords (content/2018,
# CC-BY-SA 4.0) -- not vendored, they only decide which words are common.
#
# A pyramid row is a set of letters (its "key", the letters sorted): every
# dictionary word made of exactly those letters fills the row. A pyramid is a
# chain of keys, each one the previous plus one letter, from a 3-letter key up
# to its base. words_<lang>.lua holds one line per key the generator may use,
# shortest keys first:
#
#   1AET:TEA,EAT,ATE|ETA
#
#   1 / 2     the key's tier. From a tier 1 key, removing one letter at a
#             time can reach a start key through tier 1 keys only, every one
#             with a word in the top EASY_TOP of the frequency list (Easy and
#             Medium). Tier 2 keys do the same through any key of the file,
#             with words in the top CORE_TOP (Hard). Keys that reach no start
#             key are left out: no pyramid can use them.
#   before |  the common words (top CORE_TOP), most frequent first: the
#             answer a hint or a reveal shows.
#   after |   every other dictionary word with these letters, accepted when
#             typed but never shown. Taken from every block of
#             boggle.koplugin's list: in French its second block holds the
#             Grammalecte lexicon's forms (that plugin's tools/lexicon_fr.py,
#             which filters them for family play). Keys, tiers and common
#             words only use its first block, so the pyramids do not move.
#
# A start key is a 3-letter key whose most frequent word is in the top
# START_TOP and not in START_EXCLUDE (interjections, first names, loanwords:
# fine inside a pyramid, odd as the word the puzzle starts from).
#
# Blocklisted words (blocklist.lua, the fleet's family filter) are never
# common: a pyramid never shows one, a player may still type it.
import collections, os, re, sys, unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOGGLE = os.path.join(os.path.dirname(ROOT), "boggle.koplugin")
NAMES = {"en": "English", "fr": "French"}

MIN_LEN, MAX_LEN = 3, 9
EASY_TOP = 15000
CORE_TOP = 30000
START_TOP = 5000
START_EXCLUDE = {
    "en": set("""AAH AIN ASS BEN BOB BUM COS DON GAY GEE HEH HMM HON HUH JEW JIN JOE KEN
                 MEL NAH OOH PEE REX SEC SHH SIS TED TOM UGH WHA YAY YEP YUP""".split()),
    "fr": set("""AGI AIE BAH BEN BOB BOY BYE DAN EUH FOR GAY GUS HOP HUM MAN MAX OUT
                 PRO SIR THE USA""".split()),
}


def words_of(path):
    text = open(path, encoding="utf-8").read()
    m = re.search(r"\[\[(.*?)\]\]", text, re.S)
    return [w.upper() for w in re.findall(r"[A-Za-z]+", m.group(1))]


def all_words_of(path):
    # Every [[...]] block, not only the first.
    text = open(path, encoding="utf-8").read()
    return [w.upper() for b in re.findall(r"\[\[(.*?)\]\]", text, re.S) for w in re.findall(r"[A-Za-z]+", b)]


def blocked_of(lang):
    text = open(os.path.join(ROOT, "blocklist.lua"), encoding="utf-8").read()
    m = re.search(lang + r"\s*=\s*\[\[(.*?)\]\]", text, re.S)
    return set(m.group(1).split())


def normalize(word):
    # Same normalization as the dictionaries: accents stripped, ligatures
    # spelt out, anything left that is not a-z (apostrophes, hyphens) dropped.
    w = word.lower().replace("œ", "oe").replace("æ", "ae")
    w = "".join(c for c in unicodedata.normalize("NFD", w) if unicodedata.category(c) != "Mn")
    return w.upper() if re.fullmatch(r"[a-z]+", w) else None


def key_of(word):
    return "".join(sorted(word))


def reaching(starts, keys):
    # The keys of `keys` from which removing one letter at a time reaches one
    # of `starts`, every key on the way in `keys`.
    good = set(starts)
    for n in range(MIN_LEN + 1, MAX_LEN + 1):
        for k in keys:
            if len(k) == n and any(k[:i] + k[i + 1:] in good for i in range(n)):
                good.add(k)
    return good


def build(lang, freq_path):
    words = {w for w in words_of(os.path.join(BOGGLE, f"words_{lang}.lua"))
             if MIN_LEN <= len(w) <= MAX_LEN}
    blocked = blocked_of(lang)
    accepted = {w for w in all_words_of(os.path.join(BOGGLE, f"words_{lang}.lua"))
                if MIN_LEN <= len(w) <= MAX_LEN}

    rank = {}
    for line in open(freq_path, encoding="utf-8"):
        parts = line.split()
        w = parts and normalize(parts[0])
        if w and w not in rank:
            rank[w] = len(rank)
    common = {w for w in words if rank.get(w, CORE_TOP) < CORE_TOP and w not in blocked}

    by_key = collections.defaultdict(list)
    for w in accepted:
        by_key[key_of(w)].append(w)
    top = {}
    for w in sorted(common, key=lambda w: (rank[w], w)):
        top.setdefault(key_of(w), []).append(w)

    starts = {k for k, ws in top.items()
              if len(k) == MIN_LEN and rank[ws[0]] < START_TOP and ws[0] not in START_EXCLUDE[lang]}
    easy = reaching(starts, {k for k, ws in top.items() if rank[ws[0]] < EASY_TOP})
    hard = reaching(starts, set(top))

    lines, counts = [], collections.Counter()
    for k in sorted(hard, key=lambda k: (len(k), k)):
        rest = sorted(w for w in by_key[k] if w not in common)
        lines.append(("1" if k in easy else "2") + k + ":" + ",".join(top[k]) + "|" + ",".join(rest))
        counts[(len(k), k in easy)] += 1

    per_len = ", ".join(f"{n}: {counts[(n, True)]}+{counts[(n, False)]}"
                        for n in range(MIN_LEN, MAX_LEN + 1))
    name = NAMES[lang]
    source = {
        "en": "ENABLE (Public Domain)",
        "fr": "the CC0 Scrabble-valid list + an-array-of-french-words (MIT),\n"
              "-- plus for rare words the Grammalecte lexicon (MPL 2.0)",
    }[lang]
    with open(os.path.join(ROOT, f"words_{lang}.lua"), "w", encoding="utf-8") as f:
        f.write(f"""-- {name} letter sets for Letter Pyramid (generated, do not edit).
-- Words from boggle.koplugin/words_{lang}.lua, i.e. {source}; see that
-- file for the full credits. Common words: in the top {CORE_TOP} of the
-- OpenSubtitles frequency list (hermitdave/FrequencyWords, CC-BY-SA 4.0),
-- minus blocklist.lua. Line format: tools/build_words.py.
-- Keys by length, tier 1 + tier 2: {per_len}.
-- Regenerate with tools/build_words.py (run from the monorepo root).
return [[
{chr(10).join(lines)}
]]
""")
    print(lang, "keys:", len(lines), "(" + per_len + ")")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: build_words.py EN_FREQ FR_FREQ")
    build("en", sys.argv[1])
    build("fr", sys.argv[2])
