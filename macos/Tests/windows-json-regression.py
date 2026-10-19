#!/usr/bin/env python3
"""Exercise the Windows production parser on macOS with only platform declarations stubbed.

This verifies UTF-16 code units and parser behavior, not a Windows/MSVC build.
"""
from pathlib import Path
import subprocess

repo = Path(__file__).resolve().parents[2]
source_dir = repo / 'windows/src/translation'
build_dir = repo / 'macos/.build/windows-json-regressions'
build_dir.mkdir(parents=True, exist_ok=True)
header = (source_dir / 'TranslationService.h').read_text().replace('#pragma once', '').replace('#include "../core/Globals.h"', '')
source = (source_dir / 'TranslationService.cpp').read_text().replace('#include "TranslationService.h"', '').replace('#include "../core/Globals.h"', '')
stubs = r'''
#include <string>
#include <vector>
#include <cwchar>
#include <iostream>
#include <cstdlib>
enum class LOTranslationMode { Fluent, Native, Literal };
template<size_t N> int swprintf_s(wchar_t (&buffer)[N], const wchar_t* format, unsigned value) {
    return std::swprintf(buffer, N, format, value);
}
'''
tests = r'''
int checks = 0;
void check(bool condition, const char* label) {
    if (!condition) { std::cerr << "FAIL: " << label << "\n"; std::exit(1); }
    ++checks;
    std::cout << "PASS: " << label << "\n";
}
int main() {
    LOJsonValue root;
    check(LOParseJson("{\"text\":\"hello\"}", root) && root.Find(L"text")->AsString() == L"hello", "simple object");
    check(LOParseJson("\"\\u4f60\\u597d\"", root) && root.strVal == L"你好", "BMP Unicode escapes");
    check(LOParseJson("\"\\ud83c\\udf0d\"", root) && root.strVal.size() == 2 && root.strVal[0] == 0xd83c && root.strVal[1] == 0xdf0d, "escaped emoji yields UTF-16 surrogate pair");
    std::wstring escaped = root.strVal;
    check(LOParseJson("\"\xf0\x9f\x8c\x8d\"", root) && root.strVal == escaped, "UTF-8 emoji matches escaped surrogate pair");
    check(!LOParseJson("\"\\ud83c\"", root), "unpaired high surrogate rejected");
    check(!LOParseJson("\"\\udf0d\"", root), "unpaired low surrogate rejected");
    check(!LOParseJson("\"\\ud83c\\u0041\"", root), "invalid surrogate pair rejected");
    check(!LOParseJson("\"\xc0\xaf\"", root), "overlong UTF-8 rejected");
    check(!LOParseJson("\"\xed\xa0\x80\"", root), "UTF-8 encoded surrogate rejected");
    check(!LOParseJson("\"\xf4\x90\x80\x80\"", root), "out of range Unicode rejected");
    check(!LOParseJson("\"raw\nnewline\"", root), "unescaped control character rejected");
    for (const auto& input : {"01", "1.", "1e", "+1", "1-2", ".5", "--1"})
        check(!LOParseJson(input, root), input);
    check(LOParseJson("[-0.25,1e-2,true,false,null] \r\n", root) && root.arrVal.size() == 5, "valid JSON numbers and literals");
    std::string deep(65, '['); deep += "0"; deep += std::string(65, ']');
    check(!LOParseJson(deep, root), "excess nesting rejected");
    check(LOParseJson("{\"old\":1}", root), "first reused object parse");
    check(LOParseJson("{\"new\":2}", root) && root.Find(L"old") == nullptr && root.Find(L"new") != nullptr, "reused output cleared between parses");
    check(!LOParseJson("{\"a\":1} garbage", root), "trailing junk rejected");
    std::cout << checks << " Windows parser regression checks passed (portable harness, not MSVC).\n";
}
'''
combined = build_dir / 'WindowsJsonRegression.cpp'
combined.write_text(stubs + header + source + tests)
program = build_dir / 'windows-json-regressions'
subprocess.run(['clang++', '-std=c++17', '-Wall', '-Wextra', '-fsanitize=address,undefined', '-g', str(combined), '-o', str(program)], check=True)
subprocess.run([str(program)], check=True)
