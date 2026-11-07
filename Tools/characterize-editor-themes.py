#!/usr/bin/env python3
"""Run only the checked-in original style parser as development evidence.

PEG Markdown Highlight: Copyright 2011-2013 Ali Rantakari, MIT option.
Full notice: LICENSE/peg-markdown-highlight.txt. No C parser enters Snowfolio.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

WRAPPER = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "pmh_styleparser.h"
#include "pmh_parser.h"
static void rule(const char *name, pmh_style_attribute *a) {
    if (!a) return;
    printf("R\t%s\n", name);
    for (; a; a=a->next) {
        printf("A\t%s\t%d\t", a->type == pmh_attr_type_other ? a->name : pmh_attr_name_from_type(a->type), a->type);
        switch (a->type) {
        case pmh_attr_type_foreground_color: case pmh_attr_type_background_color: case pmh_attr_type_caret_color:
            printf("%02x%02x%02x%02x",a->value->argb_color->alpha,a->value->argb_color->red,a->value->argb_color->green,a->value->argb_color->blue); break;
        case pmh_attr_type_font_size_pt: printf("%d:%d",a->value->font_size->is_relative,a->value->font_size->size_pt); break;
        case pmh_attr_type_font_family: printf("%s",a->value->font_family); break;
        case pmh_attr_type_font_style: printf("%d",a->value->font_styles->bold + 2*a->value->font_styles->italic + 4*a->value->font_styles->underlined); break;
        default: printf("%s",a->value->string);
        }
        putchar('\n');
    }
}
int main(int argc,char **argv) {
    if (argc!=2) return 2;
    FILE *f=fopen(argv[1],"rb"); if (!f) return 3;
    fseek(f,0,SEEK_END); long n=ftell(f); rewind(f);
    char *s=calloc(n+1,1); fread(s,1,n,f); fclose(f);
    pmh_style_collection *c=pmh_parse_styles(s,NULL,NULL);
    rule("editor",c->editor_styles); rule("editor-current-line",c->editor_current_line_styles); rule("editor-selection",c->editor_selection_styles);
    for (int i=0;i<pmh_NUM_LANG_TYPES;i++) {
        pmh_style_attribute *a=c->element_styles[i];
        if (a) rule(pmh_element_name_from_type(a->lang_element_type),a);
    }
    pmh_free_style_collection(c); free(s); return 0;
}
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    original = root / 'Dependency/peg-markdown-highlight'
    head = (original / 'pmh_parser_head.c').read_text()
    # Extract byte-identical original name-table functions, without compiling
    # any original Markdown parser or changing the original style parser.
    names = head[head.index('static char **get_element_type_names()'):]
    names = names[:names.index('\n\n\n', names.index('char *pmh_element_name_from_type'))]
    sources = [(p.name, p.read_text()) for p in sorted((root / 'MacDown/Resources/Themes').glob('*.style'))]
    sources += [
        ('aliases-and-ARGB', 'editor\ncolor = 80112233\nbackground-color: FFFFFF\ncaret-color: 000000\n\nH1\nfont-size: +3px\nfont-family: Menlo\nfont-style: BOLD, Italic, Underlined\ncustom-property: retained\n'),
        ('BOM-and-CRLF', '\ufeff# comment\r\neditor\r\nforeground: abcDEF # inline\r\n\r\nH2\rfont-size: -2pt\r'),
        ('duplicate-attributes', 'editor\nforeground: 112233\ncolor: 445566\n\nSTRONG\nfont-style: bold\nfont-style: italic\n\nSTRONG\nforeground: aabbcc\n'),
        ('duplicate-editor-blocks', 'editor\nforeground: 112233\n\neditor\nbackground: aabbcc\n'),
        ('unknown-and-invalid', 'not-a-rule\nforeground: ffffff\n\nH1\nforeground: bad\nfont-size: nope\nfont-style: bold, sideways\n\nEMPH\nforeground: 010203\n'),
        ('case-sensitive-names', 'h1\nforeground: 010203\n\nH1\nForeground: abcdef\nFONT-SIZE: 24px\n'),
    ]
    cases = []
    with tempfile.TemporaryDirectory(prefix='snowfolio-style-capture-') as tmp:
        temp = Path(tmp)
        (temp / 'names.c').write_text('#include <stdlib.h>\n#include <string.h>\n#include "pmh_parser.h"\n' + names)
        (temp / 'capture.c').write_text(WRAPPER)
        exe = temp / 'capture'
        subprocess.run(['xcrun','clang','-I',str(original),str(original / 'pmh_styleparser.c'),str(temp / 'names.c'),str(temp / 'capture.c'),'-o',str(exe)],check=True)
        for name, source in sources:
            path = temp / 'input.style'
            path.write_bytes(source.encode())
            output = subprocess.check_output([str(exe),str(path)],text=True)
            rules = []
            for line in output.splitlines():
                fields = line.split('\t',3)
                if fields[0]=='R': rules.append({'selector':fields[1], 'attributes':[]})
                else: rules[-1]['attributes'].append({'name':fields[1], 'kind':int(fields[2]), 'value':fields[3]})
            cases.append({'name':name,'source':source,'rules':rules})
    provenance = {name:hashlib.sha256((original / name).read_bytes()).hexdigest()
                  for name in ['pmh_styleparser.c','pmh_styleparser.h','pmh_parser_head.c','pmh_parser.h','pmh_definitions.h']}
    args.output.write_text(json.dumps({'engine':'Vendored PEG Markdown Highlight style parser', 'notice':'LICENSE/peg-markdown-highlight.txt', 'sourceSHA256':provenance, 'cases':cases},ensure_ascii=False,indent=2)+'\n')


if __name__=='__main__':
    main()
