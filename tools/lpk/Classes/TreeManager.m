//
//  TreeManager.m
//  lpk
//
//  Created by maruojie on 15/2/16.
//  Copyright (c) 2015年 luma. All rights reserved.
//

#import "TreeManager.h"
#import "NSArray+Transform.h"
#import "ProgressViewController.h"
#import "NSMutableData+ReadWrite.h"
#import "NSData+Generator.h"

@interface TreeManager ()

- (uint32_t)nextPOT:(uint32_t)x;
- (uint32_t)nextFreeHashIndex:(lpk_file*)f from:(uint32_t)from;

@end

@implementation TreeManager

- (id)init {
    if(self = [super init]) {
        self.root = [[LpkEntry alloc] init];
        self.exportPath = @"";
        self.projectPath = [@"~/Documents/Untitled.lpkproj" stringByExpandingTildeInPath];
        return self;
    }
    return nil;
}

- (void)addFiles:(NSArray*)paths toDir:(LpkEntry*)dir {
    // use root if dir is nil
    if(!dir) {
        dir = self.root;
    }
    
    // add every file, depends on it is folder or file
    for(NSString* path in paths) {
        LpkEntry* e = [[LpkEntry alloc] initWithPath:path];
        if(e) {
            // add to dir
            [dir addChild:e];
            
            // if it is dir also, add recursively
            if(e.isDir) {
                NSFileManager* fm = [NSFileManager defaultManager];
                NSArray* tmp = [fm contentsOfDirectoryAtPath:path error:nil];
                NSArray* subpaths = [tmp arrayByApplyingBlock:^id(id s) {
                    return [path stringByAppendingPathComponent:s];
                }];
                [self addFiles:subpaths toDir:e];
            }
        }
    }
    
    // sort
    [dir sortChildrenRecursively];
    
    // flag
    self.dirty = YES;
}

- (LpkEntry*)entryByKey:(NSString*)key {
    NSArray* parts = [key componentsSeparatedByString:@"/"];
    LpkEntry* e = self.root;
    for(NSString* name in parts) {
        if([@"" isEqualToString:name])
            continue;
        e = [e childByName:name];
        if(!e)
            break;
    }
    return e;
}

- (NSArray*)stripContainedKeys:(NSArray*)keys {
    // get folder entries
    NSArray* folders = [keys arrayByApplyingBlock:^id(id key) {
        LpkEntry* e = [self entryByKey:key];
        if(e && e.isDir) {
            return e;
        } else {
            return nil;
        }
    }];
    
    // remove file entries in folders
    return [keys arrayByApplyingBlock:^id(id key) {
        LpkEntry* e = [self entryByKey:key];
        if(e) {
            if(![e isContainedByAnyDir:folders]) {
                return e;
            }
        }
        
        return nil;
    }];
}

- (NSArray*)stripContainedEntries:(NSArray*)entries {
    // get folder entries
    NSArray* folders = [entries arrayByApplyingBlock:^id(id obj) {
        LpkEntry* e = (LpkEntry*)obj;
        if(e && e.isDir) {
            return e;
        } else {
            return nil;
        }
    }];
    
    // remove file entries in folders
    return [entries arrayByApplyingBlock:^id(id obj) {
        LpkEntry* e = (LpkEntry*)obj;
        if(e) {
            if(![e isContainedByAnyDir:folders]) {
                return e;
            }
        }
        
        return nil;
    }];
}

- (void)moveEntryByKeys:(NSArray*)keys toDir:(LpkEntry*)dir {
    // use root if dir is nil
    if(!dir) {
        dir = self.root;
    }
    
    // strip contained entries
    NSArray* ndupEntries = [self stripContainedKeys:keys];
    
    // move every entry
    NSMutableArray* affectedParents = [NSMutableArray array];
    for(LpkEntry* e in ndupEntries) {
        // detach entry from parent
        if(dir != e.parent && dir != e) {
            [affectedParents addObject:e.parent];
            [e removeFromParent];
            [dir addChild:e];
        }
    }
    
    // resort changed entry
    for(LpkEntry* e in affectedParents) {
        [e sortChildren];
    }
    
    // sort
    [dir sortChildren];
    
    // flag
    self.dirty = YES;
}

- (void)removeEntries:(NSArray*)entries {
    // strip contained entries
    NSArray* ndupEntries = [self stripContainedEntries:entries];
    
    // remove every entry
    for(LpkEntry* e in ndupEntries) {
        [e removeFromParent];
    }
    
    // flag
    self.dirty = YES;
}

- (void)removeEntry:(LpkEntry*)e {
    [e removeFromParent];
    self.dirty = YES;
}

- (void)removeBranch:(LpkBranchEntry*)b ofEntry:(LpkEntry*)e {
    [e.branches removeObject:b];
    self.dirty = YES;
}

- (void)newFolder:(NSString*)name toDir:(LpkEntry*)dir {
    // create entry
    LpkEntry* e = [[LpkEntry alloc] initWithFolderName:name];
    
    // use root if dir is nil
    if(!dir) {
        dir = self.root;
    }
    
    // add
    [dir addChild:e];
    
    // sort
    [dir sortChildren];
    
    // flag
    self.dirty = YES;
}

- (void)loadProject {
    NSDictionary* dict = [NSDictionary dictionaryWithContentsOfFile:self.projectPath];
    if(dict) {
        self.root = [LpkEntry decodeWithDictionary:dict];
        
        // flag
        self.dirty = NO;
    }
}

- (void)saveProject {
    NSError* err = nil;
    NSOutputStream* os = [NSOutputStream outputStreamToFileAtPath:self.projectPath append:NO];
    [os open];
    NSMutableDictionary* root = [NSMutableDictionary dictionary];
    [self.root encodeWithDictionary:root relativeTo:[self.projectPath stringByDeletingLastPathComponent]];
    if(![NSPropertyListSerialization writePropertyList:root
                                              toStream:os
                                                format:NSPropertyListXMLFormat_v1_0
                                               options:0
                                                 error:&err]) {
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setMessageText:[err localizedDescription]];
        [alert beginSheetModalForWindow:[[NSApplication sharedApplication] mainWindow] completionHandler:nil];
    } else {
        self.dirty = NO;
    }
    [os close];
}

- (void)exportLPK:(ProgressViewController*)pvc {
    NSFileManager* fm = [NSFileManager defaultManager];
    if(![fm fileExistsAtPath:self.exportPath]) {
        [fm createFileAtPath:self.exportPath contents:[NSData data] attributes:nil];
    } else {
        [fm removeItemAtPath:self.exportPath error:nil];
        [fm createFileAtPath:self.exportPath contents:[NSData data] attributes:nil];
    }
    NSFileHandle* fh = [NSFileHandle fileHandleForWritingAtPath:self.exportPath];
    NSMutableData* buf = [NSMutableData data];
    
    // progress hint
    pvc.hintLabel.stringValue = @"Prepare for exporting...";
    
    // init part of file struct
    lpk_file lpk = { 0 };
    lpk.h.lpk_magic = LPK_MAGIC;
    lpk.h.header_size = sizeof(lpk_header);
    lpk.h.block_size = 3;
    lpk.files = [self.root getFileCountIncludeBranch];
    lpk.h.hash_table_count = [self nextPOT:lpk.files];
    lpk.h.block_table_count = [self nextPOT:lpk.files];
    lpk.het = (lpk_hash*)calloc(lpk.h.hash_table_count, sizeof(lpk_hash));
    lpk.bet = (lpk_block*)calloc(lpk.h.block_table_count, sizeof(lpk_block));
    for(int i = 0; i < lpk.h.hash_table_count; i++) {
        lpk.het[i].block_table_index = LPK_HASH_FREE;
        lpk.het[i].next_hash = LPK_HASH_FREE;
        lpk.het[i].prev_hash = LPK_HASH_FREE;
    }
    
    // progress hint
    pvc.hintLabel.stringValue = @"Writting header...";
    
    // write header
    [buf writeUInt32:lpk.h.lpk_magic];
    [buf writeUInt32:lpk.h.header_size];
    [buf writeUInt32:lpk.h.archive_size];
    [buf writeUInt16:lpk.h.version];
    [buf writeUInt16:lpk.h.block_size];
    [buf writeUInt32:lpk.h.hash_table_offset];
    [buf writeUInt32:lpk.h.block_table_offset];
    [buf writeUInt32:lpk.h.hash_table_count];
    [buf writeUInt32:lpk.h.block_table_count];
    [fh writeData:buf];
    [buf setLength:0];
    
    // get a list of all entries
    NSMutableArray* allFileEntries = [NSMutableArray array];
    [self.root collectFiles:allFileEntries];
    
    // start to write every file, but not include branch at first
    uint32_t totalSize = 0;
    uint32_t blockIndex = 0;
    uint32_t blockSize = (uint32_t)(512 * pow(2, lpk.h.block_size));
    NSMutableArray* postponeFileEntries = [NSMutableArray array];
    for(LpkEntry* e in allFileEntries) {
        // get hash table index for this entry
        NSString* eKey = e.key;
        const void* key = (const void*)[eKey cStringUsingEncoding:NSUTF8StringEncoding];
        size_t len = [eKey lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        uint32_t hashIndex = hashlittle(key, len, LPK_HASH_TAG_TABLE_INDEX) & (lpk.h.hash_table_count - 1);
        lpk_hash* hash = lpk.het + hashIndex;
        
        // if this entry is already used, postpone this entry
        if(hash->block_table_index != LPK_HASH_FREE) {
            [postponeFileEntries addObject:e];
            continue;
        }
        
        // progress hint
        pvc.hintLabel.stringValue = [NSString stringWithFormat:@"Writting %@...", e.name];
        
        // fill hash
        LpkBranchEntry* b = [e getFirstBranch];
        hash->hash_a = hashlittle(key, len, LPK_HASH_TAG_NAME_A);
        hash->hash_b = hashlittle(key, len, LPK_HASH_TAG_NAME_B);
        hash->locale = b.locale;
        hash->platform = b.platform;
        
        // write block
        NSData* data = [NSData dataWithContentsOfFile:b.realPath];
        uint32_t fileSize = (uint32_t)[data length];
        [fh writeData:data];
        uint32_t blockCount = fileSize / blockSize;
        
        // fill junk to make it align with block size
        uint32_t junk = blockSize - (fileSize % blockSize);
        if(junk > 0) {
            [fh writeData:[NSData dataWithByte:0 repeated:junk]];
        }
        
        // fill block struct
        lpk_block* block = lpk.bet + blockIndex;
        block->file_size = fileSize;
        block->packed_size = fileSize;
        block->flags = LPK_FLAG_EXISTS;
        block->offset = totalSize;
        
        // save block index
        hash->block_table_index = blockIndex;
        
        // add total size
        totalSize += blockCount * blockSize;
        
        // move to next block
        blockIndex++;
    }
    
    // postpone entries
    uint32_t freeHashIndex = 0;
    for(LpkEntry* e in postponeFileEntries) {
        // progress hint
        pvc.hintLabel.stringValue = [NSString stringWithFormat:@"Writting %@...", e.name];
        
        // get hash table index for this entry
        NSString* eKey = e.key;
        const void* key = (const void*)[eKey cStringUsingEncoding:NSUTF8StringEncoding];
        size_t len = [eKey lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        uint32_t hashIndex = hashlittle(key, len, LPK_HASH_TAG_TABLE_INDEX) & (lpk.h.hash_table_count - 1);
        lpk_hash* hash = lpk.het + hashIndex;
        
        // find a free hash slot
        freeHashIndex = [self nextFreeHashIndex:&lpk from:freeHashIndex];
        if(freeHashIndex == LPK_HASH_FREE) {
            NSLog(@"no free hash found! that should not be occured");
            break;
        }
        lpk_hash* chainHash = lpk.het + freeHashIndex;
        
        // fill hash
        LpkBranchEntry* b = [e getFirstBranch];
        chainHash->hash_a = hashlittle(key, len, LPK_HASH_TAG_NAME_A);
        chainHash->hash_b = hashlittle(key, len, LPK_HASH_TAG_NAME_B);
        chainHash->locale = b.locale;
        chainHash->platform = b.platform;
        
        // write block
        NSData* data = [NSData dataWithContentsOfFile:b.realPath];
        uint32_t fileSize = (uint32_t)[data length];
        [fh writeData:data];
        uint32_t blockCount = fileSize / blockSize;
        
        // fill junk to make it align with block size
        uint32_t junk = blockSize - (fileSize % blockSize);
        if(junk > 0) {
            [fh writeData:[NSData dataWithByte:0 repeated:junk]];
        }
        
        // fill block struct
        lpk_block* block = lpk.bet + blockIndex;
        block->file_size = fileSize;
        block->packed_size = fileSize;
        block->flags = LPK_FLAG_EXISTS;
        block->offset = totalSize;
        
        // save block index
        chainHash->block_table_index = blockIndex;
        
        // link hash
        hash->next_hash = freeHashIndex;
        chainHash->prev_hash = hashIndex;
        
        // add total size
        totalSize += blockCount * fileSize;
        
        // move to next block
        blockIndex++;
        
        // increase free index search start
        freeHashIndex++;
    }
    
    // process branch
    for(LpkEntry* e in allFileEntries) {
        // if only one branch, already processed, just skip
        int bc = (int)[e.branches count];
        if(bc == 1) {
            continue;
        }
        
        // progress hint
        pvc.hintLabel.stringValue = [NSString stringWithFormat:@"Writting %@...", e.name];
        
        // iterate
        for(int i = 1; i < bc; i++) {
            LpkBranchEntry* b = [e.branches objectAtIndex:i];
            
            // get hash table index for this entry
            NSString* eKey = e.key;
            const void* key = (const void*)[eKey cStringUsingEncoding:NSUTF8StringEncoding];
            size_t len = [eKey lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            uint32_t hashIndex = hashlittle(key, len, LPK_HASH_TAG_TABLE_INDEX) & (lpk.h.hash_table_count - 1);
            lpk_hash* hash = lpk.het + hashIndex;
            while(hash->next_hash != LPK_HASH_FREE) {
                hash = lpk.het + hash->next_hash;
            }
            
            // find a free hash slot
            freeHashIndex = [self nextFreeHashIndex:&lpk from:freeHashIndex];
            if(freeHashIndex == LPK_HASH_FREE) {
                NSLog(@"no free hash found! that should not be occured");
                break;
            }
            lpk_hash* chainHash = lpk.het + freeHashIndex;
            
            // fill hash
            chainHash->hash_a = hashlittle(key, len, LPK_HASH_TAG_NAME_A);
            chainHash->hash_b = hashlittle(key, len, LPK_HASH_TAG_NAME_B);
            chainHash->locale = b.locale;
            chainHash->platform = b.platform;
            
            // write block
            NSData* data = [NSData dataWithContentsOfFile:b.realPath];
            uint32_t fileSize = (uint32_t)[data length];
            [fh writeData:data];
            uint32_t blockCount = fileSize / blockSize;
            
            // fill junk to make it align with block size
            uint32_t junk = blockSize - (fileSize % blockSize);
            if(junk > 0) {
                [fh writeData:[NSData dataWithByte:0 repeated:junk]];
            }
            
            // fill block struct
            lpk_block* block = lpk.bet + blockIndex;
            block->file_size = fileSize;
            block->packed_size = fileSize;
            block->flags = LPK_FLAG_EXISTS;
            block->offset = totalSize;
            
            // save block index
            chainHash->block_table_index = blockIndex;
            
            // link hash
            hash->next_hash = freeHashIndex;
            chainHash->prev_hash = hashIndex;
            
            // add total size
            totalSize += blockCount * fileSize;
            
            // move to next block
            blockIndex++;
            
            // increase free index search start
            freeHashIndex++;
        }
    }
    
    // progress hint
    pvc.hintLabel.stringValue = @"Finalizing...";
    
    // write archive size
    lpk.h.archive_size = totalSize;
    [fh seekToFileOffset:sizeof(uint32_t) * 2];
    [buf writeUInt32:lpk.h.archive_size];
    [fh writeData:buf];
    [buf setLength:0];
    
    // write hash table offset
    lpk.h.hash_table_offset = lpk.h.archive_size + sizeof(lpk_header);
    [fh seekToFileOffset:sizeof(uint32_t) * 4];
    [buf writeUInt32:lpk.h.hash_table_offset];
    [fh writeData:buf];
    [buf setLength:0];
    
    // write block table offset
    lpk.h.block_table_offset = lpk.h.hash_table_offset + sizeof(lpk_block) * lpk.h.block_table_count;
    [buf writeUInt32:lpk.h.block_table_offset];
    [fh writeData:buf];
    [buf setLength:0];
    
    // write hash entry table
    [fh seekToEndOfFile];
    [buf appendBytes:lpk.het length:sizeof(lpk_hash) * lpk.h.hash_table_count];
    [fh writeData:buf];
    [buf setLength:0];
    
    // write block table
    [buf appendBytes:lpk.bet length:sizeof(lpk_block) * lpk.h.block_table_count];
    [fh writeData:buf];
    [buf setLength:0];
    
    // close file
    [fh synchronizeFile];
    [fh closeFile];
    
    // close progress
    [pvc.view.window.sheetParent endSheet:pvc.view.window returnCode:NSModalResponseOK];
}

- (uint32_t)nextFreeHashIndex:(lpk_file*)f from:(uint32_t)from {
    for(int i = from; i < f->h.hash_table_count; i++) {
        if(f->het[i].block_table_index == LPK_HASH_FREE) {
            return i;
        }
    }
    return LPK_HASH_FREE;
}

- (uint32_t)nextPOT:(uint32_t)x {
    x = x - 1;
    x = x | (x >> 1);
    x = x | (x >> 2);
    x = x | (x >> 4);
    x = x | (x >> 8);
    x = x | (x >>16);
    return x + 1;
}

- (void)rebuildFilterChildren:(NSString*)keyword {
    [self.root rebuildFilterChildren:keyword];
}

@end
