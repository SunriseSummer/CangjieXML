# tinyxml2 端 perf 探针构建脚本
#
# 直接源码编译——把 .tinyxml2-11.0.0/tinyxml2.{cpp,h} 一并拉进来，
# 不依赖系统是否安装了 libtinyxml2，零 install 步骤即可重现。
#
# -O2 与 NDEBUG 是 C++ 端跑 perf 的"生产口径"：与 cangjie release 构建对齐，
# 避免拿带断言/调试符号的 build 与发布 build 错位比较。

TINYXML2_SRC := ../../.tinyxml2-11.0.0
CXX          ?= g++
CXXFLAGS     ?= -std=c++17 -O2 -DNDEBUG
INCLUDES     := -I$(TINYXML2_SRC)

bench: bench.cpp $(TINYXML2_SRC)/tinyxml2.cpp $(TINYXML2_SRC)/tinyxml2.h
	$(CXX) $(CXXFLAGS) $(INCLUDES) -o bench bench.cpp $(TINYXML2_SRC)/tinyxml2.cpp

clean:
	rm -f bench

.PHONY: clean
