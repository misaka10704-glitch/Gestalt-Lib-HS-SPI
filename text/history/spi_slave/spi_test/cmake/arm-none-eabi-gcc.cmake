# CLion / CMake toolchain for GD32 bare-metal builds.
# Uses GNU Tools for STM32 from STM32CubeCLT (same family as CLion embedded).

set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR arm)

set(STM32_CUBE_CLT_ROOT "/opt/ST/STM32CubeCLT_1.19.0" CACHE PATH "STM32CubeCLT install root")
set(TOOLCHAIN_BIN "${STM32_CUBE_CLT_ROOT}/GNU-tools-for-STM32/bin")

set(CMAKE_C_COMPILER   "${TOOLCHAIN_BIN}/arm-none-eabi-gcc")
set(CMAKE_CXX_COMPILER "${TOOLCHAIN_BIN}/arm-none-eabi-g++")
set(CMAKE_ASM_COMPILER "${TOOLCHAIN_BIN}/arm-none-eabi-gcc")
set(CMAKE_OBJCOPY      "${TOOLCHAIN_BIN}/arm-none-eabi-objcopy")
set(CMAKE_OBJDUMP      "${TOOLCHAIN_BIN}/arm-none-eabi-objdump")
set(CMAKE_SIZE         "${TOOLCHAIN_BIN}/arm-none-eabi-size")

set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(CMAKE_C_FLAGS_INIT
    "-mcpu=cortex-m4 -mthumb -mfloat-abi=softfp -mfpu=fpv4-sp-d16 -march=armv7e-m+fp")
set(CMAKE_CXX_FLAGS_INIT "${CMAKE_C_FLAGS_INIT}")
set(CMAKE_ASM_FLAGS_INIT "-x assembler-with-cpp")

set(CMAKE_EXE_LINKER_FLAGS_INIT
    "-mcpu=cortex-m4 -mthumb -mfloat-abi=softfp -mfpu=fpv4-sp-d16 -march=armv7e-m+fp --specs=nosys.specs --specs=nano.specs")
