#import <Foundation/Foundation.h>
#import <vmnet/vmnet.h>

bool copy_packets_contiguous(void *dst, size_t max_count, struct vmpktdesc *packets, int pktcnt, bool copy_buff);

void update_packets_ptrs(struct vmpktdesc *packets, size_t max_count, int pktcnt, int actual);

void populate_packets(struct vmpktdesc *dst, struct vmpktdesc *src, int pktcnt);

NSArray *serialize_xpc_str_array(xpc_object_t obj);

xpc_object_t unserialize_xpc_str_array(NSArray *arr);

NSDictionary *serialize_xpc_object_t(xpc_object_t obj);

xpc_object_t unserialize_xpc_object_t(NSDictionary *dict);

bool create_shared_memory(NSString **shm_name, size_t shm_size, int *shm_fd, void **shm_ptr);

bool open_shared_memory(NSString *shm_name, size_t shm_size, int *shm_fd, void **shm_ptr);

void close_shared_memory(NSString *shm_name, size_t shm_size, int shm_fd, void *shm_ptr);
