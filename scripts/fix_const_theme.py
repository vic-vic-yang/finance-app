"""
批量移除 const 修饰符：凡是 const 表达式里引用了动态 AppColors 字段
(primary / primaryLight / bg / surface / text1 / text2 / border) 的，
把外层最近的那个 const 去掉。
"""
import re
from pathlib import Path

DYNAMIC = r'AppColors\.(primary|primaryLight|bg|surface|text1|text2|border)\b'
ROOT = Path(__file__).resolve().parent.parent / 'lib'

def find_matching_paren(src, open_idx):
    """从开括号位置返回对应闭括号位置（处理嵌套 + 字符串）"""
    depth = 0
    i = open_idx
    in_str = None
    while i < len(src):
        c = src[i]
        if in_str:
            if c == '\\':
                i += 2
                continue
            if c == in_str:
                in_str = None
        else:
            if c in ('"', "'"):
                in_str = c
            elif c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    return -1

def remove_offending_const(src):
    """循环找 const XXX(...)，如果 (...) 里有动态 AppColors，去掉那个 const"""
    # const 后面接构造器：const Name(...) 或 const Name.foo(...)
    # 命名构造器/类型参数也要兼顾：const List<...>[, const Map<...>{, const ColorScheme.light(...)
    # 这里只关心 const 后面是 大写字母开头的标识符 + ( 或 < 或 [ 或 { 的情况
    pattern = re.compile(r'\bconst\s+([A-Z][\w.]*)\s*(?:<[^>]+>\s*)?[\(\[\{]')
    changed = True
    iter_count = 0
    while changed and iter_count < 20:
        changed = False
        iter_count += 1
        for m in list(pattern.finditer(src)):
            open_char = src[m.end() - 1]
            close_char = {'(': ')', '[': ']', '{': '}'}[open_char]
            # 找匹配的结束位置
            depth = 0
            i = m.end() - 1
            end = -1
            in_str = None
            while i < len(src):
                c = src[i]
                if in_str:
                    if c == '\\':
                        i += 2
                        continue
                    if c == in_str:
                        in_str = None
                else:
                    if c in ('"', "'"):
                        in_str = c
                    elif c == open_char:
                        depth += 1
                    elif c == close_char:
                        depth -= 1
                        if depth == 0:
                            end = i
                            break
                i += 1
            if end == -1:
                continue
            content = src[m.end() - 1:end + 1]
            if re.search(DYNAMIC, content):
                # 去掉这一处的 const（保留前导空白）
                const_start = m.start()
                # 找 const 这个词的开始
                after_const = m.start() + len('const')
                # 删除 'const' + 后面的空白（保留一个空格供分隔）
                new_src = src[:const_start] + src[after_const:].lstrip(' \t')
                # 但我们要在剩余部分前面加个空格，避免跟前面的字符粘连？
                # 实际上 const 前必有空白或行首，直接删 const + 后续空白是安全的
                src = new_src
                changed = True
                break  # 重新扫描
    return src, iter_count

def process(path: Path):
    text = path.read_text(encoding='utf-8')
    new_text, iters = remove_offending_const(text)
    if new_text != text:
        path.write_text(new_text, encoding='utf-8')
        return True, iters
    return False, iters

if __name__ == '__main__':
    total = 0
    for f in ROOT.rglob('*.dart'):
        changed, iters = process(f)
        if changed:
            print(f'fixed: {f.relative_to(ROOT)}  (iters={iters})')
            total += 1
    print(f'\nTotal files changed: {total}')
