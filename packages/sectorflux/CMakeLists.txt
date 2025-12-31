cmake_minimum_required(VERSION 3.20)
project(SectorFlux VERSION 1.0.0 LANGUAGES CXX C)

configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/src/version.hpp.in
    ${CMAKE_CURRENT_BINARY_DIR}/generated/version.hpp
    @ONLY
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_path(asio_INCLUDE_DIR asio.hpp)
find_package(Crow REQUIRED)
find_package(nlohmann_json REQUIRED)
find_package(httplib REQUIRED)
find_package(SQLite3 REQUIRED)
find_package(Python3 REQUIRED COMPONENTS Interpreter)
find_package(Threads REQUIRED)

add_custom_command(
    OUTPUT ${CMAKE_CURRENT_SOURCE_DIR}/src/embedded_ui.hpp
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/scripts/embed_ui.py
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/scripts/embed_ui.py
            ${CMAKE_CURRENT_SOURCE_DIR}/public/index.html
            ${CMAKE_CURRENT_SOURCE_DIR}/public/app.js
            ${CMAKE_CURRENT_SOURCE_DIR}/public/api.js
            ${CMAKE_CURRENT_SOURCE_DIR}/public/style.css
    COMMENT "Embedding UI files into C++ header"
)

add_executable(SectorFlux
    src/main.cpp
    src/proxy.cpp
    src/database.cpp
    src/embedded_ui.hpp
)

target_include_directories(SectorFlux PRIVATE src ${CMAKE_CURRENT_BINARY_DIR}/generated)
target_include_directories(SectorFlux SYSTEM PRIVATE ${asio_INCLUDE_DIR})

target_link_libraries(SectorFlux PRIVATE
    Crow::Crow
    nlohmann_json::nlohmann_json
    httplib::httplib
    SQLite::SQLite3
    Threads::Threads
)

if(NOT MSVC)
    target_compile_options(SectorFlux PRIVATE -Wall -Wextra)
endif()

install(TARGETS SectorFlux DESTINATION bin)
