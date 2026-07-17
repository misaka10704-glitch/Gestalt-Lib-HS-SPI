#include <errno.h>
#include <sys/stat.h>
#include <unistd.h>

#include "uart_console.h"

extern char _end;
static char *heap_end = 0;

int _write(int file, char *ptr, int len)
{
    (void)file;
    for (int i = 0; i < len; i++) {
        uart_putc(ptr[i]);
    }
    return len;
}

int _read(int file, char *ptr, int len)
{
    (void)file;
    (void)ptr;
    (void)len;
    return 0;
}

int _close(int file)
{
    (void)file;
    return -1;
}

int _fstat(int file, struct stat *st)
{
    (void)file;
    st->st_mode = S_IFCHR;
    return 0;
}

int _isatty(int file)
{
    (void)file;
    return 1;
}

int _lseek(int file, int ptr, int dir)
{
    (void)file;
    (void)ptr;
    (void)dir;
    return 0;
}

void *_sbrk(int incr)
{
    char *prev_heap_end;

    if (heap_end == 0) {
        heap_end = &_end;
    }

    prev_heap_end = heap_end;
    heap_end += incr;
    return (void *)prev_heap_end;
}

void _exit(int status)
{
    (void)status;
    while (1) {
    }
}

void _kill(int pid, int sig)
{
    (void)pid;
    (void)sig;
    _exit(-1);
}

int _getpid(void)
{
    return 1;
}
