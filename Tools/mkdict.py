#!/usr/bin/env python3
"""Build Shelf's dictionary (Resources/dict.sqlite) from OpenRussian's CSV
dump and the Russian National Corpus frequency list.

    python3 -I Tools/mkdict.py <folder with nouns.csv verbs.csv adjectives.csv others.csv> \
                                <freqrnc2011.csv or ''> <output.sqlite>

OpenRussian (en.openrussian.org; CSV mirror github.com/Badestrand/russian-dictionary,
CC BY-SA 4.0): tab-separated, one lemma a row, with its English glosses and every
inflected form (stress marked with ' after the vowel). The frequency list
(Lyashevskaya & Sharoff 2009, dict.ruslang.ru/freq.php; tab-separated Lemma, PoS,
Freq(ipm), R, D, Doc) gives each lemma its rank by ipm; a lemma not in it has none.

The file is read by 10.9's SQLite 3.7, so nothing newer than that: plain tables,
plain indexes.

    words(id INTEGER PRIMARY KEY, bare TEXT, accented TEXT, type TEXT, rank INTEGER, gloss TEXT)
    forms(form TEXT, word_id INTEGER)        every form, bare and lowercase, the lemma itself included
"""
import csv, io, os, sqlite3, sys

FILES = (('nouns.csv', 'noun'), ('verbs.csv', 'verb'), ('adjectives.csv', 'adjective'), ('others.csv', 'other'))
NOT_FORMS = {'bare', 'accented', 'translations_en', 'translations_de', 'gender', 'partner', 'animate', 'indeclinable',
             'sg_only', 'pl_only', 'aspect'}
MAX_SENSES = 3

# others.csv has no form tables, so the pronouns' cases are listed here (the
# words a learner meets most, in every line).
PRONOUN_FORMS = {
    'я': 'меня мне мной мною', 'ты': 'тебя тебе тобой тобою', 'он': 'его него ему нему им ним нём нем',
    'она': 'её неё ее нее ей ней ею нею', 'оно': 'его него ему нему им ним нём нем', 'мы': 'нас нам нами',
    'вы': 'вас вам вами', 'они': 'их них им ним ими ними', 'кто': 'кого кому кем ком', 'что': 'чего чему чем чём чем',
    'себя': 'себе собой собою', 'никто': 'никого никому никем', 'ничто': 'ничего ничему ничем',
    'кто-то': 'кого-то кому-то кем-то ком-то', 'что-то': 'чего-то чему-то чем-то чём-то',
    'кто-нибудь': 'кого-нибудь кому-нибудь кем-нибудь ком-нибудь', 'что-нибудь': 'чего-нибудь чему-нибудь чем-нибудь чём-нибудь',
    'сколько': 'скольких скольким сколькими', 'столько': 'стольких стольким столькими',
}


def bare(form):
    return form.replace("'", '').replace('`', '').strip().lower()


def read_text(path):
    data = open(path, 'rb').read()
    try:
        return data.decode('utf-8')
    except UnicodeDecodeError:
        return data.decode('cp1251')


def ranks(path):
    """lemma -> rank (1 = most frequent), by ipm, from the RNC list; {} without one."""
    if not path or not os.path.exists(path):
        return {}
    rows = []
    text = read_text(path)
    lines = text.splitlines()
    header = [h.strip().lower() for h in lines[0].split('\t')]
    li = header.index('lemma') if 'lemma' in header else 0
    fi = next((i for i, h in enumerate(header) if h.startswith('freq')), 2)
    for line in lines[1:]:
        parts = line.split('\t')
        if len(parts) <= max(li, fi):
            continue
        try:
            ipm = float(parts[fi].replace(',', '.'))
        except ValueError:
            continue
        rows.append((ipm, parts[li].strip().lower()))
    rows.sort(key=lambda r: -r[0])
    out = {}
    for n, (ipm, lemma) in enumerate(rows, 1):
        out.setdefault(lemma, n)        # a lemma listed under two parts of speech keeps its better rank
    return out


def glosses(text):
    senses = [s.strip() for s in text.split(';') if s.strip()]
    return '; '.join(senses[:MAX_SENSES])


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    folder, freq, out = sys.argv[1:]
    rank = ranks(freq)
    if os.path.exists(out):
        os.remove(out)
    db = sqlite3.connect(out)
    db.execute('CREATE TABLE words (id INTEGER PRIMARY KEY, bare TEXT NOT NULL, accented TEXT NOT NULL, type TEXT NOT NULL, '
               'rank INTEGER, gloss TEXT NOT NULL)')
    db.execute('CREATE TABLE forms (form TEXT NOT NULL, word_id INTEGER NOT NULL)')
    words = forms = skipped = 0
    seen_forms = set()
    for name, kind in FILES:
        path = os.path.join(folder, name)
        if not os.path.exists(path):
            print('no %s' % name, file=sys.stderr)
            continue
        with io.open(path, encoding='utf-8', newline='') as f:
            reader = csv.DictReader(f, delimiter='\t', quoting=csv.QUOTE_NONE)
            for row in reader:
                b = bare(row.get('bare') or '')
                en = glosses(row.get('translations_en') or '')
                if not b or not en:
                    skipped += 1
                    continue
                accented = (row.get('accented') or b).strip()
                r = rank.get(b) or rank.get(b.replace('ё', 'е'))     # the RNC list writes ё as е
                cur = db.execute('INSERT INTO words (bare, accented, type, rank, gloss) VALUES (?, ?, ?, ?, ?)',
                                 (b, accented, kind, r, en))
                wid = cur.lastrowid
                words += 1
                all_forms = {b}
                all_forms.update(PRONOUN_FORMS.get(b, '').split())
                for column, value in row.items():
                    if column in NOT_FORMS or column is None or not value:
                        continue
                    for piece in value.replace('/', ',').split(','):
                        fb = bare(piece)
                        if fb and ' ' not in fb:
                            all_forms.add(fb)
                # Subtitles often write ё as е: both spellings find the word.
                for fb in list(all_forms):
                    if 'ё' in fb:
                        all_forms.add(fb.replace('ё', 'е'))
                for fb in all_forms:
                    if (fb, wid) in seen_forms:
                        continue
                    seen_forms.add((fb, wid))
                    db.execute('INSERT INTO forms (form, word_id) VALUES (?, ?)', (fb, wid))
                    forms += 1
    db.execute('CREATE INDEX forms_form ON forms (form)')
    db.execute('CREATE INDEX words_bare ON words (bare)')
    db.commit()
    db.execute('VACUUM')
    db.close()
    ranked = sqlite3.connect(out).execute('SELECT COUNT(*) FROM words WHERE rank IS NOT NULL').fetchone()[0]
    print('%s: %d words (%d ranked), %d forms, %d rows skipped (no English), %.1f MB' %
          (out, words, ranked, forms, skipped, os.path.getsize(out) / 1e6))


if __name__ == '__main__':
    main()
