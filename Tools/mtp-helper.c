#include <libmtp.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <unistd.h>

static void print_usage(void) {
  fprintf(stderr, "用法:\n");
  fprintf(stderr, "  mtp-helper serve\n");
  fprintf(stderr, "  mtp-helper probe\n");
  fprintf(stderr, "  mtp-helper refresh [current-storage-id-hex]\n");
  fprintf(stderr, "  mtp-helper list-storages\n");
  fprintf(stderr, "  mtp-helper list-files <storage-id-hex> [parent-id]\n");
  fprintf(stderr, "  mtp-helper send-file <local-path> <storage-id-hex> <remote-name> [parent-id]\n");
  fprintf(stderr, "  mtp-helper get-file <item-id> <local-path>\n");
  fprintf(stderr, "  mtp-helper create-folder <storage-id-hex> <parent-id> <name>\n");
}

static void with_silent_stdout(void (*fn)(void));

static LIBMTP_mtpdevice_t *open_device_inner(void) {
  LIBMTP_Init();
  int saw_device = 0;

  for (int attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) {
      usleep(300 * 1000);
    }

    LIBMTP_raw_device_t *raw_devices = NULL;
    int device_count = 0;
    LIBMTP_error_number_t detect_result = LIBMTP_Detect_Raw_Devices(&raw_devices, &device_count);
    int found = (detect_result == LIBMTP_ERROR_NONE && device_count > 0);
    if (found) {
      saw_device = 1;
      LIBMTP_mtpdevice_t *device = LIBMTP_Open_Raw_Device_Uncached(&raw_devices[0]);
      if (raw_devices != NULL) {
        free(raw_devices);
      }
      if (device != NULL) {
        return device;
      }
    } else if (raw_devices != NULL) {
      free(raw_devices);
    }
  }

  if (saw_device) {
    fprintf(stderr, "无法打开 MTP 设备。设备可能正被其他程序独占占用（例如浏览器的 WebUSB），请先断开或退出该程序后重试。\n");
  } else {
    fprintf(stderr, "没有找到 MTP 设备。请确认 Switch 已打开 DBI MTP 响应器。\n");
  }
  return NULL;
}

static LIBMTP_mtpdevice_t *g_open_result = NULL;

static void open_device_wrapped(void) {
  g_open_result = open_device_inner();
}

static LIBMTP_mtpdevice_t *open_device(void) {
  g_open_result = NULL;
  with_silent_stdout(open_device_wrapped);
  return g_open_result;
}

/* 执行 fn 期间把 stdout 重定向到 /dev/null，吞掉 libmtp 检测时的打印噪音。
   注意：必须在恢复 fd 1 之前 fflush，否则缓冲的噪音会在恢复后泄漏出来。 */
static void with_silent_stdout(void (*fn)(void)) {
  fflush(stdout);
  int devnull = open("/dev/null", O_WRONLY);
  if (devnull < 0) {
    fn();
    return;
  }
  int saved = dup(STDOUT_FILENO);
  dup2(devnull, STDOUT_FILENO);
  fn();
  fflush(stdout);
  dup2(saved, STDOUT_FILENO);
  close(saved);
  close(devnull);
}

static void do_nothing(void) {}

static uint32_t parse_u32(const char *value) {
  return (uint32_t) strtoul(value, NULL, 0);
}

/* 根目录在 MTP 协议里是 0xffffffff，不是 0。 */
static uint32_t resolve_parent(uint32_t parent_id) {
  return parent_id == 0 ? LIBMTP_FILES_AND_FOLDERS_ROOT : parent_id;
}

static void print_clean(const char *value) {
  if (value == NULL) {
    return;
  }
  for (const char *cursor = value; *cursor != '\0'; cursor++) {
    if (*cursor == '\t' || *cursor == '\n' || *cursor == '\r') {
      putchar(' ');
    } else {
      putchar(*cursor);
    }
  }
}

/*
 * 仅做 USB 层检测，不打开 MTP 会话。用来判断设备是否在线，
 * 不会在 Switch 的 DBI 响应器上触发“会话打开/关闭”。
 * 退出码 0 = 找到设备；1 = 没有设备。
 */
static int probe_result = 1;

static void probe_impl(void) {
  LIBMTP_Init();
  LIBMTP_raw_device_t *raw_devices = NULL;
  int device_count = 0;
  LIBMTP_error_number_t detect_result = LIBMTP_Detect_Raw_Devices(&raw_devices, &device_count);
  if (raw_devices != NULL) {
    free(raw_devices);
  }
  probe_result = (detect_result == LIBMTP_ERROR_NONE && device_count > 0) ? 0 : 1;
}

static int probe(void) {
  with_silent_stdout(probe_impl);
  return probe_result;
}

static int storage_has_install_name(LIBMTP_devicestorage_t *storage) {
  return storage->StorageDescription != NULL &&
         strcasestr(storage->StorageDescription, "SD Card install") != NULL;
}

/*
 * 与 Swift 端 preferredStorageID 的逻辑保持一致：
 * 保留当前选中的存储区，其次优先 “SD Card install”，
 * 再次优先可写存储区，最后取第一个存储区。
 */
static LIBMTP_devicestorage_t *preferred_storage(LIBMTP_devicestorage_t *head, const char *current_id_text) {
  uint32_t current_id = (current_id_text != NULL && current_id_text[0] != '\0') ? parse_u32(current_id_text) : 0;
  LIBMTP_devicestorage_t *first = NULL;
  LIBMTP_devicestorage_t *writable = NULL;
  LIBMTP_devicestorage_t *install = NULL;

  for (LIBMTP_devicestorage_t *s = head; s != NULL; s = s->next) {
    if (first == NULL) {
      first = s;
    }
    if (current_id != 0 && s->id == current_id) {
      return s;
    }
    if (install == NULL && storage_has_install_name(s)) {
      install = s;
    }
    if (writable == NULL && s->AccessCapability == 0) {
      writable = s;
    }
  }

  if (install != NULL) {
    return install;
  }
  if (writable != NULL) {
    return writable;
  }
  return first;
}

/* 与 mtp-detect 输出格式保持一致，供 Swift 端解析设备摘要。 */
static void print_device_summary(LIBMTP_mtpdevice_t *device) {
  printf("Device recognized as MTP\n");
  char *value = NULL;

  value = LIBMTP_Get_Manufacturername(device);
  if (value != NULL && value[0] != '\0') {
    printf("Manufacturer: ");
    print_clean(value);
    printf("\n");
  }
  value = LIBMTP_Get_Modelname(device);
  if (value != NULL && value[0] != '\0') {
    printf("Model: ");
    print_clean(value);
    printf("\n");
  }
  value = LIBMTP_Get_Deviceversion(device);
  if (value != NULL && value[0] != '\0') {
    printf("Device version: ");
    print_clean(value);
    printf("\n");
  }
  value = LIBMTP_Get_Serialnumber(device);
  if (value != NULL && value[0] != '\0') {
    printf("Serial number: ");
    print_clean(value);
    printf("\n");
  }
  value = LIBMTP_Get_Friendlyname(device);
  if (value != NULL && value[0] != '\0') {
    printf("Friendly name: ");
    print_clean(value);
    printf("\n");
  }
  if (device->extensions != NULL) {
    printf("Vendor extension description: ");
    for (LIBMTP_device_extension_t *ext = device->extensions; ext != NULL; ext = ext->next) {
      printf("%s: %d.%d", ext->name != NULL ? ext->name : "", ext->major, ext->minor);
      if (ext->next != NULL) {
        printf("; ");
      }
    }
    printf("\n");
  }
}

/*
 * 单次会话内完成一次完整刷新：设备信息 + 全部存储区 + 首选存储区的根目录。
 */
static int refresh_on(LIBMTP_mtpdevice_t *device, const char *current_id_text) {
  print_device_summary(device);

  if (LIBMTP_Get_Storage(device, LIBMTP_STORAGE_SORTBY_NOTSORTED) != 0) {
    LIBMTP_Dump_Errorstack(device);
    return 3;
  }

  LIBMTP_devicestorage_t *preferred = preferred_storage(device->storage, current_id_text);

  for (LIBMTP_devicestorage_t *storage = device->storage; storage != NULL; storage = storage->next) {
    printf("STORAGE\t0x%08x\t", storage->id);
    print_clean(storage->StorageDescription);
    printf("\t%llu\t%llu\t%u\n",
           (unsigned long long) storage->FreeSpaceInBytes,
           (unsigned long long) storage->MaxCapacity,
           storage->AccessCapability);
  }

  if (preferred != NULL) {
    LIBMTP_Clear_Errorstack(device);
    LIBMTP_file_t *files = LIBMTP_Get_Files_And_Folders(device, preferred->id, LIBMTP_FILES_AND_FOLDERS_ROOT);
    if (files == NULL && LIBMTP_Get_Errorstack(device) != NULL) {
      LIBMTP_Dump_Errorstack(device);
      LIBMTP_destroy_file_t(files);
      return 8;
    }
    for (LIBMTP_file_t *file = files; file != NULL; file = file->next) {
      printf("FILE\t%u\t%u\t0x%08x\t%u\t%llu\t",
             file->item_id,
             file->parent_id,
             file->storage_id,
             file->filetype,
             (unsigned long long) file->filesize);
      print_clean(file->filename);
      printf("\n");
    }
    LIBMTP_destroy_file_t(files);
  }

  return 0;
}

static int list_storages_on(LIBMTP_mtpdevice_t *device) {
  if (LIBMTP_Get_Storage(device, LIBMTP_STORAGE_SORTBY_NOTSORTED) != 0) {
    LIBMTP_Dump_Errorstack(device);
    return 3;
  }

  for (LIBMTP_devicestorage_t *storage = device->storage; storage != NULL; storage = storage->next) {
    printf("STORAGE\t0x%08x\t", storage->id);
    print_clean(storage->StorageDescription);
    printf("\t%llu\t%llu\t%u\n",
           (unsigned long long) storage->FreeSpaceInBytes,
           (unsigned long long) storage->MaxCapacity,
           storage->AccessCapability);
  }

  return 0;
}

static int list_files_on(LIBMTP_mtpdevice_t *device, const char *storage_id_text, uint32_t parent_id) {
  uint32_t storage_id = parse_u32(storage_id_text);
  parent_id = resolve_parent(parent_id);

  /* DBI 响应器必须先 Get_Storage 才会对存储区执行 GetObjectHandles。 */
  if (LIBMTP_Get_Storage(device, LIBMTP_STORAGE_SORTBY_NOTSORTED) != 0) {
    LIBMTP_Dump_Errorstack(device);
    return 3;
  }

  LIBMTP_Clear_Errorstack(device);
  LIBMTP_file_t *files = LIBMTP_Get_Files_And_Folders(device, storage_id, parent_id);

  if (files == NULL && LIBMTP_Get_Errorstack(device) != NULL) {
    LIBMTP_Dump_Errorstack(device);
    LIBMTP_destroy_file_t(files);
    return 8;
  }

  for (LIBMTP_file_t *file = files; file != NULL; file = file->next) {
    printf("FILE\t%u\t%u\t0x%08x\t%u\t%llu\t",
           file->item_id,
           file->parent_id,
           file->storage_id,
           file->filetype,
           (unsigned long long) file->filesize);
    print_clean(file->filename);
    printf("\n");
  }

  LIBMTP_destroy_file_t(files);
  return 0;
}

static int send_file_on(LIBMTP_mtpdevice_t *device, const char *local_path, const char *storage_id_text, const char *remote_name, uint32_t parent_id) {
  struct stat file_stat;
  if (stat(local_path, &file_stat) != 0) {
    perror("无法读取本地文件");
    return 4;
  }

  /* DBI 需要先 Get_Storage 才能接收文件。 */
  if (LIBMTP_Get_Storage(device, LIBMTP_STORAGE_SORTBY_NOTSORTED) != 0) {
    LIBMTP_Dump_Errorstack(device);
    return 3;
  }

  LIBMTP_file_t *metadata = LIBMTP_new_file_t();
  metadata->filename = strdup(remote_name);
  metadata->filesize = (uint64_t) file_stat.st_size;
  metadata->filetype = LIBMTP_FILETYPE_UNKNOWN;
  metadata->storage_id = parse_u32(storage_id_text);
  metadata->parent_id = resolve_parent(parent_id);

  int result = LIBMTP_Send_File_From_File(device, local_path, metadata, NULL, NULL);
  if (result != 0) {
    LIBMTP_Dump_Errorstack(device);
    LIBMTP_destroy_file_t(metadata);
    return 5;
  }

  printf("OK\t0x%08x\t", metadata->storage_id);
  print_clean(metadata->filename);
  printf("\n");

  LIBMTP_destroy_file_t(metadata);
  return 0;
}

static int get_file_on(LIBMTP_mtpdevice_t *device, const char *item_id_text, const char *local_path) {
  int result = LIBMTP_Get_File_To_File(device, parse_u32(item_id_text), local_path, NULL, NULL);
  if (result != 0) {
    LIBMTP_Dump_Errorstack(device);
    return 6;
  }
  printf("OK\t%s\n", local_path);
  return 0;
}

static int create_folder_on(LIBMTP_mtpdevice_t *device, const char *storage_id_text, uint32_t parent_id, char *name) {
  /* DBI 需要先 Get_Storage 才能创建目录。 */
  if (LIBMTP_Get_Storage(device, LIBMTP_STORAGE_SORTBY_NOTSORTED) != 0) {
    LIBMTP_Dump_Errorstack(device);
    return 3;
  }

  uint32_t folder_id = LIBMTP_Create_Folder(device, name, resolve_parent(parent_id), parse_u32(storage_id_text));
  if (folder_id == 0) {
    LIBMTP_Dump_Errorstack(device);
    return 7;
  }
  printf("FOLDER\t%u\n", folder_id);
  return 0;
}

/* 错误栈里是否有 USB/连接级错误（说明设备可能已丢失，需要重开会话）。 */
static int has_device_level_error(LIBMTP_mtpdevice_t *device) {
  for (LIBMTP_error_t *e = LIBMTP_Get_Errorstack(device); e != NULL; e = e->next) {
    if (e->errornumber == LIBMTP_ERROR_USB_LAYER ||
        e->errornumber == LIBMTP_ERROR_CONNECTING ||
        e->errornumber == LIBMTP_ERROR_NO_DEVICE_ATTACHED) {
      return 1;
    }
  }
  return 0;
}

/*
 * 常驻会话模式：一次打开设备并保持 MTP 会话，命令从 stdin 以制表符分隔的
 * 行输入，结果输出到 stdout，每条命令以 "\n__END__\t<exit-code>" 结尾。
 * DBI 的对象 ID 只在枚举出它们的会话内有效，因此浏览子目录必须复用同一会话。
 * 空闲超过 120 秒自动退出（Swift 端每 60 秒发一次 probe 保活）。
 */
static int serve(void) {
  LIBMTP_mtpdevice_t *device = NULL;
  char *line = NULL;
  size_t cap = 0;
  int ret = 0;

  for (;;) {
    struct pollfd pfd = { .fd = STDIN_FILENO, .events = POLLIN };
    int pr = poll(&pfd, 1, 120000);
    if (pr == 0) {
      break; /* 空闲超时，退出 */
    }
    if (pr < 0) {
      if (errno == EINTR) {
        continue;
      }
      break;
    }

    if (getline(&line, &cap, stdin) == -1) {
      break;
    }

    size_t len = strlen(line);
    while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) {
      line[--len] = '\0';
    }
    if (len == 0) {
      continue;
    }

    char *saveptr = NULL;
    char *cmd = strtok_r(line, "\t", &saveptr);
    if (cmd == NULL) {
      continue;
    }

    int code = 64;

    if (strcmp(cmd, "quit") == 0 || strcmp(cmd, "exit") == 0) {
      ret = 0;
      break;
    } else if (strcmp(cmd, "probe") == 0) {
      code = probe();
    } else if (strcmp(cmd, "refresh") == 0) {
      char *cur = strtok_r(NULL, "\t", &saveptr);
      if (device == NULL) {
        device = open_device();
      }
      if (device == NULL) {
        code = 2;
      } else {
        code = refresh_on(device, cur != NULL ? cur : "");
      }
    } else if (strcmp(cmd, "list-storages") == 0) {
      if (device == NULL) {
        device = open_device();
      }
      if (device == NULL) {
        code = 2;
      } else {
        code = list_storages_on(device);
      }
    } else if (strcmp(cmd, "list-files") == 0) {
      char *sid = strtok_r(NULL, "\t", &saveptr);
      char *pid = strtok_r(NULL, "\t", &saveptr);
      if (sid == NULL) {
        code = 64;
      } else {
        if (device == NULL) {
          device = open_device();
        }
        if (device == NULL) {
          code = 2;
        } else {
          code = list_files_on(device, sid, pid != NULL ? parse_u32(pid) : LIBMTP_FILES_AND_FOLDERS_ROOT);
        }
      }
    } else if (strcmp(cmd, "send-file") == 0) {
      char *path = strtok_r(NULL, "\t", &saveptr);
      char *sid = strtok_r(NULL, "\t", &saveptr);
      char *name = strtok_r(NULL, "\t", &saveptr);
      char *pid = strtok_r(NULL, "\t", &saveptr);
      if (path == NULL || sid == NULL || name == NULL) {
        code = 64;
      } else {
        if (device == NULL) {
          device = open_device();
        }
        if (device == NULL) {
          code = 2;
        } else {
          code = send_file_on(device, path, sid, name, pid != NULL ? parse_u32(pid) : LIBMTP_FILES_AND_FOLDERS_ROOT);
        }
      }
    } else if (strcmp(cmd, "get-file") == 0) {
      char *iid = strtok_r(NULL, "\t", &saveptr);
      char *path = strtok_r(NULL, "\t", &saveptr);
      if (iid == NULL || path == NULL) {
        code = 64;
      } else {
        if (device == NULL) {
          device = open_device();
        }
        if (device == NULL) {
          code = 2;
        } else {
          code = get_file_on(device, iid, path);
        }
      }
    } else if (strcmp(cmd, "create-folder") == 0) {
      char *sid = strtok_r(NULL, "\t", &saveptr);
      char *pid = strtok_r(NULL, "\t", &saveptr);
      char *name = strtok_r(NULL, "\t", &saveptr);
      if (sid == NULL || pid == NULL || name == NULL) {
        code = 64;
      } else {
        if (device == NULL) {
          device = open_device();
        }
        if (device == NULL) {
          code = 2;
        } else {
          code = create_folder_on(device, sid, parse_u32(pid), name);
        }
      }
    }

    /* 设备级错误时释放会话，下一条命令会重新打开（自愈）。 */
    if (device != NULL && code != 0 && has_device_level_error(device)) {
      LIBMTP_Release_Device(device);
      device = NULL;
    }

    printf("\n__END__\t%d\n", code);
    fflush(stdout);
  }

  free(line);
  if (device != NULL) {
    LIBMTP_Release_Device(device);
  }
  return ret;
}

int main(int argc, char **argv) {
  if (argc < 2) {
    print_usage();
    return 64;
  }

  if (strcmp(argv[1], "serve") == 0) {
    return serve();
  }

  if (strcmp(argv[1], "probe") == 0) {
    if (argc != 2) {
      print_usage();
      return 64;
    }
    return probe();
  }

  if (strcmp(argv[1], "refresh") == 0) {
    if (argc != 2 && argc != 3) {
      print_usage();
      return 64;
    }
    LIBMTP_mtpdevice_t *device = open_device();
    if (device == NULL) {
      return 2;
    }
    int code = refresh_on(device, argc == 3 ? argv[2] : "");
    LIBMTP_Release_Device(device);
    return code;
  }

  if (strcmp(argv[1], "list-storages") == 0) {
    if (argc != 2) {
      print_usage();
      return 64;
    }
    LIBMTP_mtpdevice_t *device = open_device();
    if (device == NULL) {
      return 2;
    }
    int code = list_storages_on(device);
    LIBMTP_Release_Device(device);
    return code;
  }

  if (strcmp(argv[1], "list-files") == 0) {
    if (argc != 3 && argc != 4) {
      print_usage();
      return 64;
    }
    LIBMTP_mtpdevice_t *device = open_device();
    if (device == NULL) {
      return 2;
    }
    int code = list_files_on(device, argv[2], argc == 4 ? parse_u32(argv[3]) : LIBMTP_FILES_AND_FOLDERS_ROOT);
    LIBMTP_Release_Device(device);
    return code;
  }

  if (strcmp(argv[1], "send-file") == 0) {
    if (argc != 5 && argc != 6) {
      print_usage();
      return 64;
    }
    LIBMTP_mtpdevice_t *device = open_device();
    if (device == NULL) {
      return 2;
    }
    int code = send_file_on(device, argv[2], argv[3], argv[4], argc == 6 ? parse_u32(argv[5]) : LIBMTP_FILES_AND_FOLDERS_ROOT);
    LIBMTP_Release_Device(device);
    return code;
  }

  if (strcmp(argv[1], "get-file") == 0) {
    if (argc != 4) {
      print_usage();
      return 64;
    }
    LIBMTP_mtpdevice_t *device = open_device();
    if (device == NULL) {
      return 2;
    }
    int code = get_file_on(device, argv[2], argv[3]);
    LIBMTP_Release_Device(device);
    return code;
  }

  if (strcmp(argv[1], "create-folder") == 0) {
    if (argc != 5) {
      print_usage();
      return 64;
    }
    LIBMTP_mtpdevice_t *device = open_device();
    if (device == NULL) {
      return 2;
    }
    int code = create_folder_on(device, argv[2], parse_u32(argv[3]), argv[4]);
    LIBMTP_Release_Device(device);
    return code;
  }

  print_usage();
  return 64;
}
