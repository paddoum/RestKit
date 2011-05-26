//
//  RKObjectSeeder.m
//  RestKit
//
//  Created by Blake Watters on 3/4/10.
//  Copyright 2010 Two Toasters. All rights reserved.
//

#if TARGET_OS_IPHONE
#import <MobileCoreServices/UTType.h>
#endif

#import "RKManagedObjectSeeder.h"
#import "RKManagedObjectStore.h"
#import "RKManagedObjectFactory.h"
#import "../ObjectMapping/RKParserRegistry.h"

@interface RKManagedObjectSeeder (Private)
- (NSString *)mimeTypeForExtension:(NSString *)extension;
- (id)initWithObjectManager:(RKObjectManager*)manager;
- (void)seedObjectsFromFileNames:(NSArray*)fileNames;
@end

NSString* const RKDefaultSeedDatabaseFileName = @"RKSeedDatabase.sqlite";

@implementation RKManagedObjectSeeder

@synthesize delegate = _delegate;

+ (void)generateSeedDatabaseWithObjectManager:(RKObjectManager*)objectManager fromFiles:(NSString*)firstFileName, ... {
    RKManagedObjectSeeder* seeder = [RKManagedObjectSeeder objectSeederWithObjectManager:objectManager];
    
    va_list args;
    va_start(args, firstFileName);
	NSMutableArray* fileNames = [NSMutableArray array];
    for (NSString* fileName = firstFileName; fileName != nil; fileName = va_arg(args, id)) {
        [fileNames addObject:fileName];
    }
    va_end(args);
    
    // Seed the files
    for (NSString* fileName in fileNames) {
        [seeder seedObjectsFromFile:fileName withObjectMapping:nil];
    }
    
    [seeder finalizeSeedingAndExit];
}

+ (RKManagedObjectSeeder*)objectSeederWithObjectManager:(RKObjectManager*)objectManager {
    return [[[RKManagedObjectSeeder alloc] initWithObjectManager:objectManager] autorelease];
}

- (id)initWithObjectManager:(RKObjectManager*)manager {
    self = [self init];
	if (self) {
		_manager = [manager retain];
        
        // If the user hasn't configured an object store, set one up for them
        if (nil == _manager.objectStore) {
            _manager.objectStore = [RKManagedObjectStore objectStoreWithStoreFilename:RKDefaultSeedDatabaseFileName];
        }
        
        // Delete any existing persistent store
        [_manager.objectStore deletePersistantStore];
	}
	
	return self;
}

- (void)dealloc {
	[_manager release];
	[super dealloc];
}

- (NSString*)pathToSeedDatabase {
    return _manager.objectStore.pathToStoreFile;
}

- (void)seedObjectsFromFiles:(NSString*)firstFileName, ... {
    va_list args;
    va_start(args, firstFileName);
	NSMutableArray* fileNames = [NSMutableArray array];
    for (NSString* fileName = firstFileName; fileName != nil; fileName = va_arg(args, id)) {
        [fileNames addObject:fileName];
    }
    va_end(args);
    
    for (NSString* fileName in fileNames) {
        [self seedObjectsFromFile:fileName withObjectMapping:nil];
    }
}

- (void)seedObjectsFromFile:(NSString*)fileName withObjectMapping:(RKObjectMapping *)nilOrObjectMapping {
    NSError* error = nil;
	NSString* filePath = [[NSBundle mainBundle] pathForResource:fileName ofType:nil];
	NSString* payload = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:&error];
    
	if (payload) {
        NSString* MIMEType = [self mimeTypeForExtension:[fileName pathExtension]];
        if (MIMEType == nil) {
            // Default the MIME type to the value of the Accept header if we couldn't detect it...
            MIMEType = _manager.acceptMIMEType;
        }
        id<RKParser> parser = [[RKParserRegistry sharedRegistry] parserForMIMEType:MIMEType];
        NSAssert1(parser, @"Could not find a parser for the MIME Type '%@'", MIMEType);
        id parsedData = [parser objectFromString:payload error:&error];        
        NSAssert(parsedData, @"Cannot perform object load without data for mapping");
        
        RKObjectMappingProvider* mappingProvider = nil;
        if (nilOrObjectMapping) {
            mappingProvider = [[RKObjectMappingProvider new] autorelease];
            [mappingProvider setMapping:nilOrObjectMapping forKeyPath:@""];
        } else {
            mappingProvider = _manager.mappingProvider;
        }
        
        RKObjectMapper* mapper = [RKObjectMapper mapperWithObject:parsedData mappingProvider:mappingProvider];
        mapper.objectFactory = [RKManagedObjectFactory objectFactoryWithObjectStore:_manager.objectStore];
        RKObjectMappingResult* result = [mapper performMapping];
        if (result == nil) {
            NSLog(@"Database seeding from file '%@' failed due to object mapping errors: %@", fileName, mapper.errors);
            return;
        }
        
        NSArray* mappedObjects = [result asCollection];
		NSAssert1([mappedObjects isKindOfClass:[NSArray class]], @"Expected an NSArray of objects, got %@", mappedObjects);
        
        // Inform the delegate
        if (self.delegate) {
            for (NSManagedObject* object in mappedObjects) {
                [self.delegate didSeedObject:object fromFile:fileName];
            }
        }
        
		NSLog(@"[RestKit] RKManagedObjectSeeder: Seeded %d objects from %@...", [mappedObjects count], [NSString stringWithFormat:@"%@", fileName]);
	} else {
		NSLog(@"Unable to read file %@: %@", fileName, [error localizedDescription]);
	}
}

- (void)finalizeSeedingAndExit {
	NSError* error = [[_manager objectStore] save];
	if (error != nil) {
		NSLog(@"[RestKit] RKManagedObjectSeeder: Error saving object context: %@", [error localizedDescription]);
	}
	
	NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString* basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
	NSString* storeFileName = [[_manager objectStore] storeFilename];
	NSString* destinationPath = [basePath stringByAppendingPathComponent:storeFileName];
	NSLog(@"[RestKit] RKManagedObjectSeeder: A seeded database has been generated at '%@'. "
          @"Please execute `open \"%@\"` in your Terminal and copy %@ to your app. Be sure to add the seed database to your \"Copy Resources\" build phase.", 
          destinationPath, basePath, storeFileName);
	
	exit(1);
}

- (NSString *)mimeTypeForExtension:(NSString *)extension {
	if (NULL != UTTypeCreatePreferredIdentifierForTag) {
		CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)extension, NULL);
		if (uti != NULL) {
			CFStringRef mime = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType);
			CFRelease(uti);
			if (mime != NULL) {
				NSString *type = [NSString stringWithString:(NSString *)mime];
				CFRelease(mime);
				return type;
			}
		}
	}
	
    return nil;
}

@end
