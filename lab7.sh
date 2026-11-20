#!/bin/bash

# ==============================================================================
# Практическая работа № 7
# Тема: Изучение принципов разработки программ на языке командной оболочки Bash
# Автор: Глинин В. Е., группа ККСО-22-25
# ==============================================================================

# Флаги действий и пути перенаправления
DO_USERS=0
DO_PROCESSES=0
LOG_FILE=""
ERR_FILE=""

# ------------------------------------------------------------------------------
# Функция фильтрации и вывода сообщений из stderr внешних команд
# ------------------------------------------------------------------------------
handle_command_stderr() {
    local cmd_name="$1"
    local raw_err="$2"
    local filtered_err

    # Удаляем пустые строки и лишние префиксы/служебные предупреждения
    filtered_err=$(printf '%s\n' "$raw_err" | sed -e '/^[[:space:]]*$/d' -e "s/^${cmd_name}:[[:space:]]*//")

    if [ -n "$filtered_err" ]; then
        printf 'Ошибка (%s): %s\n' "$cmd_name" "$filtered_err" >&2
    else
        printf 'Ошибка (%s): команда завершилась с ошибкой.\n' "$cmd_name" >&2
    fi
}

# ------------------------------------------------------------------------------
# Функция проверки доступности пути для записи файла
# ------------------------------------------------------------------------------
validate_output_path() {
    local target_path="$1"
    local purpose="$2"
    local target_dir

    if [ -z "$target_path" ]; then
        echo "Ошибка: Не указан путь для $purpose." >&2
        return 1
    fi

    if [ -d "$target_path" ]; then
        echo "Ошибка: Путь '$target_path' для $purpose является директорией, а не файлом." >&2
        return 1
    fi

    target_dir=$(dirname "$target_path")

    if [ ! -d "$target_dir" ]; then
        echo "Ошибка: Директория '$target_dir' для $purpose не существует." >&2
        return 1
    fi

    if [ ! -x "$target_dir" ]; then
        echo "Ошибка: Отсутствуют права на доступ к каталогу '$target_dir' для $purpose." >&2
        return 1
    fi

    if [ -e "$target_path" ]; then
        if [ ! -w "$target_path" ]; then
            echo "Ошибка: Отсутствуют права на запись в существующий файл '$target_path' ($purpose)." >&2
            return 1
        fi
    else
        if [ ! -w "$target_dir" ]; then
            echo "Ошибка: Отсутствуют права на запись в каталог '$target_dir' для создания файла ($purpose)." >&2
            return 1
        fi
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Функция вывода справочной информации (-h, --help)
# ------------------------------------------------------------------------------
show_help() {
    cat << EOF
Использование: $0 [ПАРАМЕТРЫ]

Консольная утилита для вывода списка пользователей и запущенных процессов ОС.

Параметры:
  -u, --users             Вывести перечень пользователей и их домашних директорий,
                          отсортированных по алфавиту.
  -p, --processes         Вывести перечень запущенных процессов,
                          отсортированных по их идентификатору (PID).
  -h, --help              Вывести данную справку и завершить работу.
  -l PATH, --log PATH     Заместить вывод на экран (stdout) выводом в файл PATH.
  -e PATH, --errors PATH  Заместить вывод ошибок (stderr) выводом в файл PATH.

Примеры использования:
  $0 -u
  $0 --processes
  $0 -u -l /tmp/users.log -e /tmp/errors.log
  $0 -p --log ./processes.log --errors ./errors.log
EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Функция настройки перенаправления потока ошибок (-e, --errors)
# ------------------------------------------------------------------------------
set_error_output() {
    local target_path="$1"

    if ! validate_output_path "$target_path" "файла ошибок"; then
        exit 1
    fi

    # Замещаем поток stderr (дескриптор 2) файлом target_path
    if ! exec 2> "$target_path"; then
        echo "Ошибка: Не удалось открыть файл ошибок '$target_path' для записи." >&2
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# Функция настройки перенаправления стандартного вывода (-l, --log)
# ------------------------------------------------------------------------------
set_log_output() {
    local target_path="$1"

    if ! validate_output_path "$target_path" "файла вывода"; then
        exit 1
    fi

    # Замещаем поток stdout (дескриптор 1) файлом target_path
    if ! exec 1> "$target_path"; then
        echo "Ошибка: Не удалось открыть файл вывода '$target_path' для записи." >&2
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# Функция вывода списка пользователей и их домашних каталогов (-u, --users)
# ------------------------------------------------------------------------------
list_users() {
    local err_tmp raw_data cmd_rc err_text
    err_tmp=$(mktemp 2>/dev/null || echo "/tmp/lab7_users_err_$$.tmp")

    if command -v getent >/dev/null 2>&1; then
        raw_data=$(getent passwd 2>"$err_tmp")
        cmd_rc=$?
    else
        raw_data=$(cat /etc/passwd 2>"$err_tmp")
        cmd_rc=$?
    fi

    err_text=$(cat "$err_tmp" 2>/dev/null)
    rm -f "$err_tmp" 2>/dev/null

    if [ "$cmd_rc" -ne 0 ]; then
        handle_command_stderr "users" "$err_text"
        return 1
    fi

    echo "======================================================================"
    printf "%s\n" "ПОЛЬЗОВАТЕЛЬ              ДОМАШНЯЯ ДИРЕКТОРИЯ"
    echo "======================================================================"
    printf '%s\n' "$raw_data" | LC_ALL=C sort -t: -k1,1 | awk -F: '{printf "%-25s %s\n", $1, $6}'
    return 0
}

# ------------------------------------------------------------------------------
# Функция вывода списка процессов, отсортированных по PID (-p, --processes)
# ------------------------------------------------------------------------------
list_processes() {
    local err_tmp raw_data cmd_rc err_text
    err_tmp=$(mktemp 2>/dev/null || echo "/tmp/lab7_proc_err_$$.tmp")

    raw_data=$(ps -eo pid=,user=,comm= --sort=pid 2>"$err_tmp")
    cmd_rc=$?

    err_text=$(cat "$err_tmp" 2>/dev/null)
    rm -f "$err_tmp" 2>/dev/null

    if [ "$cmd_rc" -ne 0 ]; then
        handle_command_stderr "ps" "$err_text"
        return 1
    fi

    echo "======================================================================"
    printf "%s\n" "PID      ПОЛЬЗОВАТЕЛЬ       КОМАНДА"
    echo "======================================================================"
    printf '%s\n' "$raw_data" | awk '{
        pid = $1
        user = $2
        $1 = ""
        $2 = ""
        sub(/^[[:space:]]+/, "")
        printf "%-8s %-18s %s\n", pid, user, $0
    }'
    return 0
}

# ==============================================================================
# Разбор аргументов командной строки с использованием утилиты getopt
# ==============================================================================
GETOPT_ERR_TMP=$(mktemp 2>/dev/null || echo "/tmp/lab7_getopt_err_$$.tmp")
PARSED_ARGS=$(getopt -o uphl:e: --long users,processes,help,log:,errors: -n "$0" -- "$@" 2>"$GETOPT_ERR_TMP")
GETOPT_RC=$?
GETOPT_ERR=$(cat "$GETOPT_ERR_TMP" 2>/dev/null)
rm -f "$GETOPT_ERR_TMP" 2>/dev/null

if [ "$GETOPT_RC" -ne 0 ]; then
    handle_command_stderr "getopt" "$GETOPT_ERR"
    echo "Для получения справки используйте: $0 -h или $0 --help" >&2
    exit 1
fi

eval set -- "$PARSED_ARGS"

# Первый проход: разбор флагов и путей
while true; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        -u|--users)
            DO_USERS=1
            shift
            ;;
        -p|--processes)
            DO_PROCESSES=1
            shift
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -e|--errors)
            ERR_FILE="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Ошибка: Неизвестный параметр '$1'." >&2
            exit 1
            ;;
    esac
done

# Применение перенаправлений потоков (сначала stderr, затем stdout)
if [ -n "$ERR_FILE" ]; then
    set_error_output "$ERR_FILE"
fi

if [ -n "$LOG_FILE" ]; then
    set_log_output "$LOG_FILE"
fi

# Проверка наличия лишних позиционных аргументов
if [ $# -gt 0 ]; then
    echo "Ошибка: Неожиданные позиционные аргументы: $*" >&2
    echo "Для получения справки используйте: $0 -h или $0 --help" >&2
    exit 1
fi

# Проверка, задано ли хотя бы одно действие
if [ "$DO_USERS" -eq 0 ] && [ "$DO_PROCESSES" -eq 0 ]; then
    echo "Ошибка: Не указано ни одно действие (-u/--users или -p/--processes)." >&2
    echo "Для получения справки используйте: $0 -h или $0 --help" >&2
    exit 1
fi

# Выполнение запрошенных действий
EXIT_CODE=0

if [ "$DO_USERS" -eq 1 ]; then
    list_users || EXIT_CODE=1
fi

if [ "$DO_PROCESSES" -eq 1 ]; then
    list_processes || EXIT_CODE=1
fi

exit "$EXIT_CODE"
