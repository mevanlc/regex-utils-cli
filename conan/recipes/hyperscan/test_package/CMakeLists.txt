cmake_minimum_required(VERSION 3.24)
project(hyperscan_test_package LANGUAGES CXX)

find_package(hyperscan CONFIG REQUIRED)

add_executable(test_package test_package.cpp)
target_link_libraries(test_package PRIVATE hyperscan::hs)
target_compile_features(test_package PRIVATE cxx_std_11)
set_target_properties(test_package PROPERTIES CXX_EXTENSIONS OFF)
