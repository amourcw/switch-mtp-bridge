#include <libmtp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static void print_usage(void) {
  fprintf(stderr, "用法:\n");
  fprintf(stderr, "  mtp-helper list-storages\n");
  fprintf(stderr, "  mtp-helper list-files <storage-id-hex> [parent-id]\n");
  fprintf(stderr, "  mtp-helper send-file <local-path> <storage-id-hex> <remote-name> [parent-id]\n");
  fprintf(stderr, "  mtp-helper get-file <item-id> <local-path>\n");
  fprintf(stderr, "  mtp-helper create-folder <storage-id-hex> <parent-id> <name>\n");
}

static LIBMTP_mtpdevice_t *open_device(void) {
  LIBMTP_Init();
  LIBMTP_raw_device_t *raw_devices = NULL;
  int device_count = 0;
  LIBMTP_error_number_t detect_result = LIBMTP_Detect_Raw_Devices(&raw_devices, &device_count);
  if (detect_result != LIBMTP_ERROR_NONE || device_count < 1) {
    fprintf(stderr, "没有找到 MTP 设备。请确认 Switch 已打开 DBI MTP 响应器。\n");
    return NULL;
  }

  LIBMTP_mtpdevice_t *device = LIBMTP_Open_Raw_Device_Uncached(&raw_devices[0]);
  free(raw_devices);

  if (device == NULL) {
    fprintf(stderr, "无法打开 MTP 设备。\n");
    return NULL;
  }

  return device;
}

static uint32_t parse_u32(const char *value) {
  return (uint32_t) strtoul(value, NULL, 0);
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

static int list_storages(void) {
  LIBMTP_mtpdevice_t *device = open_device();
  if (device == NULL) {
    return 2;
  }

  if (LIBMTP_Get_Storage(device, LIBMTP_STORAGE_SORTBY_NOTSORTED) != 0) {
    LIBMTP_Dump_Errorstack(device);
    LIBMTP_Release_Device(device);
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

  LIBMTP_Release_Device(device);
  return 0;
}

static int list_files(const char *storage_id_text, uint32_t parent_id) {
  uint32_t storage_id = parse_u32(storage_id_text);
  LIBMTP_mtpdevice_t *device = open_device();
  if (device == NULL) {
    return 2;
  }

  LIBMTP_file_t *files = LIBMTP_Get_Files_And_Folders(
      device,
      storage_id,
      parent_id
  );

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
  LIBMTP_Release_Device(device);
  return 0;
}

static int send_file(const char *local_path, const char *storage_id_text, const char *remote_name, uint32_t parent_id) {
  struct stat file_stat;
  if (stat(local_path, &file_stat) != 0) {
    perror("无法读取本地文件");
    return 4;
  }

  LIBMTP_mtpdevice_t *device = open_device();
  if (device == NULL) {
    return 2;
  }

  LIBMTP_file_t *metadata = LIBMTP_new_file_t();
  metadata->filename = strdup(remote_name);
  metadata->filesize = (uint64_t) file_stat.st_size;
  metadata->filetype = LIBMTP_FILETYPE_UNKNOWN;
  metadata->storage_id = parse_u32(storage_id_text);
  metadata->parent_id = parent_id;

  int result = LIBMTP_Send_File_From_File(device, local_path, metadata, NULL, NULL);
  if (result != 0) {
    LIBMTP_Dump_Errorstack(device);
    LIBMTP_destroy_file_t(metadata);
    LIBMTP_Release_Device(device);
    return 5;
  }

  printf("OK\t0x%08x\t", metadata->storage_id);
  print_clean(metadata->filename);
  printf("\n");

  LIBMTP_destroy_file_t(metadata);
  LIBMTP_Release_Device(device);
  return 0;
}

static int get_file(const char *item_id_text, const char *local_path) {
  LIBMTP_mtpdevice_t *device = open_device();
  if (device == NULL) return 2;
  int result = LIBMTP_Get_File_To_File(device, parse_u32(item_id_text), local_path, NULL, NULL);
  if (result != 0) {
    LIBMTP_Dump_Errorstack(device);
    LIBMTP_Release_Device(device);
    return 6;
  }
  printf("OK\t%s\n", local_path);
  LIBMTP_Release_Device(device);
  return 0;
}

static int create_folder(const char *storage_id_text, uint32_t parent_id, char *name) {
  LIBMTP_mtpdevice_t *device = open_device();
  if (device == NULL) return 2;
  uint32_t folder_id = LIBMTP_Create_Folder(device, name, parent_id, parse_u32(storage_id_text));
  if (folder_id == 0) {
    LIBMTP_Dump_Errorstack(device);
    LIBMTP_Release_Device(device);
    return 7;
  }
  printf("FOLDER\t%u\n", folder_id);
  LIBMTP_Release_Device(device);
  return 0;
}

int main(int argc, char **argv) {
  if (argc < 2) {
    print_usage();
    return 64;
  }

  if (strcmp(argv[1], "list-storages") == 0) {
    return list_storages();
  }

  if (strcmp(argv[1], "list-files") == 0) {
    if (argc != 3 && argc != 4) {
      print_usage();
      return 64;
    }
    return list_files(argv[2], argc == 4 ? parse_u32(argv[3]) : LIBMTP_FILES_AND_FOLDERS_ROOT);
  }

  if (strcmp(argv[1], "send-file") == 0) {
    if (argc != 5 && argc != 6) {
      print_usage();
      return 64;
    }
    return send_file(argv[2], argv[3], argv[4], argc == 6 ? parse_u32(argv[5]) : LIBMTP_FILES_AND_FOLDERS_ROOT);
  }

  if (strcmp(argv[1], "get-file") == 0) {
    if (argc != 4) {
      print_usage();
      return 64;
    }
    return get_file(argv[2], argv[3]);
  }

  if (strcmp(argv[1], "create-folder") == 0) {
    if (argc != 5) {
      print_usage();
      return 64;
    }
    return create_folder(argv[2], parse_u32(argv[3]), argv[4]);
  }

  print_usage();
  return 64;
}
