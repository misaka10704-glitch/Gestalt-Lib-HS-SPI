cmake_minimum_required(VERSION 3.20)

project(spi_test C ASM)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# GD32 SPL from PlatformIO package (override with -DGD32_SPL_DIR=...)
if(NOT DEFINED GD32_SPL_DIR)
    set(GD32_SPL_DIR "$ENV{HOME}/.platformio/packages/framework-spl-gd32"
        CACHE PATH "Path to framework-spl-gd32")
endif()

if(NOT EXISTS "${GD32_SPL_DIR}/gd32/cmsis/variants/gd32f30x/gd32f30x.h")
    message(FATAL_ERROR
        "GD32 SPL not found at ${GD32_SPL_DIR}. "
        "Install via 'pio pkg install -g -p gd32 framework-spl-gd32' "
        "or set -DGD32_SPL_DIR=/path/to/framework-spl-gd32")
endif()

set(MCU_DEFINES
    GD32F3
    GD32F303
    GD32F30x
    GD32F30X_HD
    USE_STDPERIPH_DRIVER
)

set(COMMON_COMPILE_FLAGS
    -Os
    -ffunction-sections
    -fdata-sections
    -Wall
    -Wextra
)

set(SPL_VARIANT_DIR ${GD32_SPL_DIR}/gd32/spl/variants/gd32f30x)
set(CMSIS_VARIANT_DIR ${GD32_SPL_DIR}/gd32/cmsis/variants/gd32f30x)
set(CMSIS_CORE_DIR ${GD32_SPL_DIR}/gd32/cmsis/cores/gd32)
set(STARTUP_DIR ${GD32_SPL_DIR}/gd32/cmsis/startup_files)

file(GLOB SPL_SOURCES ${SPL_VARIANT_DIR}/src/*.c)

add_executable(${PROJECT_NAME}.elf
    src/main.c
    src/uart_console.c
    src/spi_master.c
    src/syscalls.c
    ${CMSIS_VARIANT_DIR}/system_gd32f30x.c
    ${STARTUP_DIR}/startup_gd32f30x_hd.S
    ${SPL_SOURCES}
)

target_include_directories(${PROJECT_NAME}.elf PRIVATE
    inc
    ${CMSIS_CORE_DIR}
    ${CMSIS_VARIANT_DIR}
    ${SPL_VARIANT_DIR}/inc
    ${STARTUP_DIR}
)

target_compile_definitions(${PROJECT_NAME}.elf PRIVATE ${MCU_DEFINES})
target_compile_options(${PROJECT_NAME}.elf PRIVATE ${COMMON_COMPILE_FLAGS})

set(LINKER_SCRIPT ${CMAKE_SOURCE_DIR}/linker/GD32F303C8.ld)
target_link_options(${PROJECT_NAME}.elf PRIVATE
    -T${LINKER_SCRIPT}
    -Wl,-Map=$<TARGET_FILE_DIR:${PROJECT_NAME}.elf>/${PROJECT_NAME}.map
    -Wl,--gc-sections
    -Wl,--print-memory-usage
)

add_custom_command(TARGET ${PROJECT_NAME}.elf POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O ihex $<TARGET_FILE:${PROJECT_NAME}.elf>
            ${CMAKE_BINARY_DIR}/${PROJECT_NAME}.hex
    COMMAND ${CMAKE_OBJCOPY} -O binary $<TARGET_FILE:${PROJECT_NAME}.elf>
            ${CMAKE_BINARY_DIR}/${PROJECT_NAME}.bin
    COMMAND ${CMAKE_SIZE} --format=berkeley $<TARGET_FILE:${PROJECT_NAME}.elf>
    COMMENT "Generating HEX/BIN and printing size"
)
