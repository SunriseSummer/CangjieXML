// tinyxml2 端 perf 探针：与 python / cangjie 端共用同一份 fixtures + plan.json，
// 输出与之结构一致的 JSON 到 stdout。
//
// 四个场景：parse / serialize / roundtrip / traverse。
// - parse:     XMLDocument::Parse(buf, size)
// - serialize: XMLPrinter 序列化（紧凑模式，与 fixtures 写出风格一致）
// - roundtrip: 每次都新建 doc + Parse + Print
// - traverse:  Accept 一个 Visitor，统计元素 + 属性数量
//
// 计时统一 std::chrono::steady_clock，纳秒分辨率。
//
// 命令行：bench <fixture_dir> <plan.json>
//   plan.json: [{ "file": "catalog_small.xml", "iterations": 1000 }, ...]

#include "tinyxml2.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

using namespace tinyxml2;

namespace {

struct PlanEntry {
    std::string file;
    int iterations = 0;
};

// 一个 ad-hoc 的极小 JSON 解析器——只够吃我们自己生成的 plan.json。
// 走的是"找到下一个 \"file\" 与 \"iterations\""的朴素扫描，不试图通用化。
// 选择不引入第三方 JSON 库是为了让 bench 的构建只需要 g++ + tinyxml2.cpp。
std::vector<PlanEntry> parsePlan(const std::string& text) {
    std::vector<PlanEntry> out;
    size_t pos = 0;
    while (true) {
        size_t f = text.find("\"file\"", pos);
        if (f == std::string::npos) break;
        size_t colon0 = text.find(':', f);
        size_t q1 = text.find('"', colon0);     // 值的开引号
        size_t q2 = text.find('"', q1 + 1);     // 值的闭引号
        std::string file = text.substr(q1 + 1, q2 - q1 - 1);

        size_t it = text.find("\"iterations\"", q2);
        size_t colon = text.find(':', it);
        size_t end = text.find_first_of(",}\n", colon);
        std::string num = text.substr(colon + 1, end - colon - 1);
        // 去除前后空白
        size_t a = num.find_first_not_of(" \t\r\n");
        size_t b = num.find_last_not_of(" \t\r\n");
        int iters = std::atoi(num.substr(a, b - a + 1).c_str());

        out.push_back({file, iters});
        pos = end + 1;
    }
    return out;
}

std::string slurp(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    std::ostringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

// 遍历访问者：累计元素 + 属性数。读 sink 写到全局 volatile 防 DCE。
class Counter : public XMLVisitor {
public:
    long total = 0;
    bool VisitEnter(const XMLElement& e, const XMLAttribute* first) override {
        ++total;
        for (const XMLAttribute* a = first; a != nullptr; a = a->Next()) {
            ++total;
        }
        return true;
    }
};

volatile long g_sink = 0;

double elapsedMs(const std::chrono::steady_clock::time_point& t0,
                 const std::chrono::steady_clock::time_point& t1) {
    return std::chrono::duration<double, std::milli>(t1 - t0).count();
}

void emitRecord(std::ostream& os, bool& first, const std::string& scenario,
                const std::string& fixture, int iters, double totalMs, size_t bytes) {
    if (!first) os << ",\n";
    first = false;
    os << "    {\n"
       << "      \"scenario\": \"" << scenario << "\",\n"
       << "      \"fixture\": \"" << fixture << "\",\n"
       << "      \"iterations\": " << iters << ",\n"
       << "      \"elapsed_ms_total\": " << totalMs << ",\n"
       << "      \"elapsed_ms_avg\": " << (totalMs / iters) << ",\n"
       << "      \"bytes\": " << bytes << "\n"
       << "    }";
}

void benchOne(std::ostream& os, bool& first,
              const std::string& dir, const PlanEntry& e) {
    std::string path = dir + "/" + e.file;
    std::string raw = slurp(path);
    size_t bytes = raw.size();
    int iters = e.iterations;

    // 预 parse 一份给 serialize / traverse 用——这两个场景不应重复 parse。
    XMLDocument pre;
    // Parse 接 char*，需要可写副本（tinyxml2 会原地处理），但用 size 形式即可。
    pre.Parse(raw.data(), raw.size());

    // 1. parse
    {
        auto t0 = std::chrono::steady_clock::now();
        for (int i = 0; i < iters; ++i) {
            XMLDocument d;
            d.Parse(raw.data(), raw.size());
            g_sink += (d.Error() ? 1 : 0);
        }
        auto t1 = std::chrono::steady_clock::now();
        emitRecord(os, first, "parse", e.file, iters, elapsedMs(t0, t1), bytes);
    }

    // 2. serialize
    {
        auto t0 = std::chrono::steady_clock::now();
        for (int i = 0; i < iters; ++i) {
            XMLPrinter p(nullptr, /*compact*/ true);
            pre.Print(&p);
            g_sink += p.CStrSize();
        }
        auto t1 = std::chrono::steady_clock::now();
        emitRecord(os, first, "serialize", e.file, iters, elapsedMs(t0, t1), bytes);
    }

    // 3. roundtrip
    {
        auto t0 = std::chrono::steady_clock::now();
        for (int i = 0; i < iters; ++i) {
            XMLDocument d;
            d.Parse(raw.data(), raw.size());
            XMLPrinter p(nullptr, true);
            d.Print(&p);
            g_sink += p.CStrSize();
        }
        auto t1 = std::chrono::steady_clock::now();
        emitRecord(os, first, "roundtrip", e.file, iters, elapsedMs(t0, t1), bytes);
    }

    // 4. traverse
    {
        auto t0 = std::chrono::steady_clock::now();
        for (int i = 0; i < iters; ++i) {
            Counter c;
            pre.Accept(&c);
            g_sink += c.total;
        }
        auto t1 = std::chrono::steady_clock::now();
        emitRecord(os, first, "traverse", e.file, iters, elapsedMs(t0, t1), bytes);
    }
}

}  // namespace

int main(int argc, char** argv) {
    if (argc != 3) {
        std::fprintf(stderr, "usage: bench <fixture_dir> <plan.json>\n");
        return 2;
    }
    std::string dir = argv[1];
    std::string planText = slurp(argv[2]);
    auto plan = parsePlan(planText);

    std::cout << "{\n  \"library\": \"tinyxml2-11.0.0\",\n  \"results\": [\n";
    bool first = true;
    for (const auto& e : plan) {
        benchOne(std::cout, first, dir, e);
    }
    std::cout << "\n  ]\n}\n";
    // 用一下 g_sink 防止链接器把它整个优化掉
    if (g_sink == 0xDEADBEEF) std::fprintf(stderr, "unreachable\n");
    return 0;
}
