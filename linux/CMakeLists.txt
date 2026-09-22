cmake_minimum_required(VERSION 3.24)
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/../VERSION.md" VERSION_LINES)
list(GET VERSION_LINES 2 PHOTOSCREEN_VERSION)
string(STRIP "${PHOTOSCREEN_VERSION}" PHOTOSCREEN_VERSION)
project(housecontrol-photoscreen VERSION ${PHOTOSCREEN_VERSION} LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTOUIC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 REQUIRED COMPONENTS Widgets Gui)

add_executable(housecontrol-photoscreen
    src/main.cpp
)
target_link_libraries(housecontrol-photoscreen PRIVATE Qt6::Widgets Qt6::Gui)
install(TARGETS housecontrol-photoscreen RUNTIME DESTINATION bin)
install(FILES packaging/housecontrol-photoscreen.desktop DESTINATION share/applications)

set(CPACK_PACKAGE_NAME "housecontrol-photoscreen")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "HouseControl photo slideshow")
set(CPACK_PACKAGE_CONTACT "HouseControlAU")
set(CPACK_GENERATOR "DEB")
set(CPACK_DEBIAN_PACKAGE_SECTION "graphics")
set(CPACK_DEBIAN_PACKAGE_HOMEPAGE "https://github.com/HouseControlAU/housecontrol-photoscreen")
include(CPack)
