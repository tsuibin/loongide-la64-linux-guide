/* 最小裸机入口：只验证编译/链接链路，不依赖任何 SDK。 */
void _start(void) {
    volatile int counter = 0;
    for (;;) {
        counter++;
    }
}
