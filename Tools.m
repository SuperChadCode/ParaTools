#import "Tools.h"

bool copy_packets_contiguous(void *dst, size_t max_count, struct vmpktdesc *packets, int pktcnt, bool copy_buff) {
    void *ptr = dst;
    void *back_ptr = ptr + max_count;
    void *stop = dst + max_count;
    
    size_t packets_size = pktcnt * sizeof(struct vmpktdesc);
    if (ptr + packets_size > stop) {
        return false;
    }
    memcpy(ptr, packets, packets_size);
    ptr += packets_size;
    
    for (int pktI = 0; pktI < pktcnt; pktI++) {
        struct vmpktdesc *srcPkt = &(packets[pktI]);
        
        size_t iovecs_size = srcPkt->vm_pkt_iovcnt * sizeof(struct iovec);
        if (ptr + iovecs_size > stop) {
            return false;
        }
        memcpy(ptr, srcPkt->vm_pkt_iov, iovecs_size);
        ptr += iovecs_size;
        
        for (size_t buffI = 0; buffI < srcPkt->vm_pkt_iovcnt; buffI++) {
            struct iovec *srcBuff = &(srcPkt->vm_pkt_iov[buffI]);
            
            back_ptr -= srcBuff->iov_len;
            if (back_ptr < ptr) {
                return false;
            }
            if (copy_buff) {
                memcpy(back_ptr, srcBuff->iov_base, srcBuff->iov_len);
            }
        }
    }
    
    return true;
}

void update_packets_ptrs(struct vmpktdesc *packets, size_t max_count, int pktcnt, int actual) {
    void *ptr = packets;
    void *back_ptr = ptr + max_count;
    
    ptr += pktcnt * sizeof(struct vmpktdesc);

    for (int pktI = 0; pktI < actual; pktI++) {
        struct vmpktdesc *pkt = &(packets[pktI]);
        
        pkt->vm_pkt_iov = ptr;
        
        for (size_t buffI = 0; buffI < pkt->vm_pkt_iovcnt; buffI++) {
            struct iovec *buff = &(pkt->vm_pkt_iov[buffI]);
            
            back_ptr -= buff->iov_len;
            buff->iov_base = back_ptr;
        
            ptr += sizeof(struct iovec);
        }
    }
}

void populate_packets(struct vmpktdesc *dst, struct vmpktdesc *src, int pktcnt) {
    for (int pktI = 0; pktI < pktcnt; pktI++) {
        struct vmpktdesc
        *dstPkt = &(dst[pktI]),
        *srcPkt = &(src[pktI]);
        
        // pkt size changes
        dstPkt->vm_pkt_size = srcPkt->vm_pkt_size;
        
        for (size_t buffI = 0; buffI < dstPkt->vm_pkt_iovcnt; buffI++) {
            struct iovec
            *dstBuff = &(dstPkt->vm_pkt_iov[buffI]),
            *srcBuff = &(srcPkt->vm_pkt_iov[buffI]);
            
            memcpy(dstBuff->iov_base, srcBuff->iov_base, srcBuff->iov_len);
        }
    }
}

NSArray *serialize_xpc_str_array(xpc_object_t obj) {
    if (!obj) {
        return NULL;
    }
    NSMutableArray *arr = [NSMutableArray new];
    __block bool success = true;
    xpc_array_apply(obj, ^bool(size_t index, xpc_object_t  _Nonnull value) {
        if (!value) {
            [arr addObject:[NSString new]];
        } else if (xpc_get_type(value) != XPC_TYPE_STRING) {
            NSLog(@"[ParaGreed] serialize_xpc_str_array: unexpected xpc type");
            success = false;
            return false;
        } else {
            [arr addObject:[NSString stringWithCString:xpc_string_get_string_ptr(value) encoding:NSUTF8StringEncoding]];
        }
        return true;
    });
    return success ? arr : NULL;
}

xpc_object_t unserialize_xpc_str_array(NSArray *arr) {
    if (!arr) {
        return NULL;
    }
    xpc_object_t obj = xpc_array_create(NULL, 0);
    [arr enumerateObjectsUsingBlock:^(id  _Nonnull value, NSUInteger idx, BOOL * _Nonnull stop) {
        xpc_array_append_value(obj, xpc_string_create([(NSString *)value UTF8String]));
    }];
    return obj;
}

NSDictionary *serialize_xpc_object_t(xpc_object_t obj) {
    if (!obj) {
        return NULL;
    }
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    __block bool success = true;
    xpc_dictionary_apply(obj, ^bool(const char *key, xpc_object_t value) {
        NSMutableDictionary *subDict = [NSMutableDictionary dictionary];
        xpc_type_t type = xpc_get_type(value);
        if (type == XPC_TYPE_STRING) {
            subDict[@"val"] = @(xpc_string_get_string_ptr(value));
            subDict[@"type"] = @"STRING";
        } else if (type == XPC_TYPE_UINT64) {
            subDict[@"val"] = @(xpc_uint64_get_value(value));
            subDict[@"type"] = @"UINT64";
        } else if (type == XPC_TYPE_UUID) {
            subDict[@"val"] = [NSData dataWithBytes:xpc_uuid_get_bytes(value) length:sizeof(uuid_t)];
            subDict[@"type"] = @"UUID";
        } else if (type == XPC_TYPE_BOOL) {
            subDict[@"val"] = @(xpc_bool_get_value(value));
            subDict[@"type"] = @"BOOL";
        } else {
            NSLog(@"[ParaGreed] serialize_xpc_object_t: unexpected xpc type");
            success = false;
            return false;
        }
        dict[@(key)] = subDict;
        return true;
    });
    return success ? dict : NULL;
}

xpc_object_t unserialize_xpc_object_t(NSDictionary *dict) {
    if (!dict) {
        return NULL;
    }
    xpc_object_t obj = xpc_dictionary_create(NULL, NULL, 0);
    __block bool success = true;
    [dict enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *subDict, BOOL *stop) {
        NSString *type = subDict[@"type"];
        id value = subDict[@"val"];
        if ([type isEqualToString:@"STRING"]) {
            xpc_dictionary_set_string(obj, [key UTF8String], [(NSString *)value UTF8String]);
        } else if ([type isEqualToString:@"UINT64"]) {
            xpc_dictionary_set_uint64(obj, [key UTF8String], [(NSNumber *)value unsignedLongLongValue]);
        } else if ([type isEqualToString:@"UUID"]) {
            uuid_t uuid;
            [(NSData *)value getBytes:uuid length:sizeof(uuid_t)];
            xpc_dictionary_set_uuid(obj, [key UTF8String], uuid);
        } else if ([type isEqualToString:@"BOOL"]) {
            xpc_dictionary_set_bool(obj, [key UTF8String], [(NSNumber *)value intValue]);
        } else {
            NSLog(@"[ParaGreed] unserialize_xpc_object_t: unexpected xpc type");
            success = false;
            *stop = YES;
            return;
        }
    }];
    return success ? obj : NULL;
}

bool create_shared_memory(NSString **shm_name, size_t shm_size, int *shm_fd, void **shm_ptr) {
    *shm_name = [[[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""] substringToIndex:31];
    *shm_fd = shm_open([*shm_name UTF8String], O_CREAT | O_RDWR, 0666);
    if (*shm_fd < 0) {
        return false;
    }
    if (ftruncate(*shm_fd, shm_size) == -1) {
        if (close(*shm_fd) == -1) {
            perror("close");
        }
        return false;
    }
    *shm_ptr = mmap(NULL, shm_size, PROT_READ | PROT_WRITE, MAP_SHARED, *shm_fd, 0);
    if (*shm_ptr == MAP_FAILED) {
        if (close(*shm_fd) == -1) {
            perror("close");
        }
        if (shm_unlink([*shm_name UTF8String]) == -1) {
            perror("shm_unlink");
        }
        return false;
    }
    return true;
}

bool open_shared_memory(NSString *shm_name, size_t shm_size, int *shm_fd, void **shm_ptr) {
    *shm_fd = shm_open([shm_name UTF8String], O_CREAT | O_RDWR, 0666);
    if (*shm_fd < 0) {
        return false;
    }
    *shm_ptr = mmap(NULL, shm_size, PROT_READ | PROT_WRITE, MAP_SHARED, *shm_fd, 0);
    if (*shm_ptr == MAP_FAILED) {
        if (close(*shm_fd) == -1) {
            perror("close");
        }
        if (shm_unlink([shm_name UTF8String]) == -1) {
            perror("shm_unlink");
        }
        return false;
    }
    return true;
}

void close_shared_memory(NSString *shm_name, size_t shm_size, int shm_fd, void *shm_ptr) {
    if (munmap(shm_ptr, shm_size) == -1) {
        perror("munmap");
    }
    if (close(shm_fd) == -1) {
        perror("close");
    }
    if (shm_unlink([shm_name UTF8String]) == -1) {
        perror("shm_unlink");
    }
}
