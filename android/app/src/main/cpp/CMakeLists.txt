cmake_minimum_required(VERSION 3.18.1)

project(document_scanner)

add_library(
    document_scanner
    SHARED
    document_scanner.cpp
)

find_library(
    log-lib
    log
)

target_link_libraries(
    document_scanner
    ${log-lib}
)

