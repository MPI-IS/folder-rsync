#!/usr/bin/env dub
/+ dub.sdl:
	name "folder_rsync"
	authors "Joan Josep Piles-Contreras"
	description "A naïve implementation of rsync parallelisation that splits the tasks per first-level entries."
+/

int main(string[] args)
{
	import std.stdio;
	import std.process;
	import std.parallelism : totalCPUs;
	import std.exception : enforce;
	import std.conv : to;
	import std.file;
	import std.parallelism;
	import std.algorithm.iteration : map;
	import std.algorithm.searching;
	import std.algorithm.sorting : sort;
	import std.algorithm.setops : setDifference;
	import std.algorithm.mutation;
	import std.string;
	import std.array : array, split;

	import std.experimental.logger;
	
	enum RSYNC_PARTIAL_TRANSFER = 24;
	
	alias remove = std.file.remove;
	alias removeElement = std.algorithm.mutation.remove;
	// Process environment
	
	auto logLevel = environment.get("LOG");
	if (logLevel !is null) {
		globalLogLevel = logLevel.to!LogLevel;
	}
	
	int numThreads = totalCPUs; 
	auto envNumThreads = environment.get("OMP_NUM_THREADS");
	
	if (envNumThreads != null) {
		numThreads = envNumThreads.to!int; 
	}
	
	defaultPoolThreads = numThreads - 1;
	info("Operating with ", taskPool.size + 1, " threads");

	// Process arguments
	
	auto srcArg = args[args.length - 2];
	trace("Source folder: ", srcArg);
	auto dstArg = args[args.length - 1];
	trace("Destination folder: ", dstArg);
	
	enforce(!srcArg.canFind(':') || (srcArg.countUntil(':') > srcArg.countUntil('/')), "The source folder must be local.");
	enforce(!dstArg.canFind(':') || (dstArg.countUntil(':') > dstArg.countUntil('/')), "The destination folder must be local.");
	
	auto srcHasTrailingSlash = (dstArg[$-1] == '/');

	bool mustDelete = args.canFind("--delete");
	trace("--delete found: ", mustDelete);
	
	bool dryRun = args.canFind("--dry-run");
	trace("--dry-run found: ", dryRun);
	
	auto linkDestArg = args.countUntil!"a.startsWith(\"--link-dest=\")";
	trace ("--link-dest argument found at position: ", linkDestArg);
	
	// START OPERATION
	
	// Abort if src doesn't exist or is not a folder.

	enforce(srcArg.exists, "The source directory doesn't exist");

	auto src = DirEntry(srcArg);
	enforce(src.isDir, "The source is not a directory");

	// Create dst if it doesn't exist yet
	
	if (!dstArg.exists) {
		trace("Creating destination folder ", dstArg);
		if (dryRun) {
			info("Dry run: skipping destination folder creation.");
		} else {
			mkdir(dstArg);
		}
	}

	// If there is no slash, we have to create the directory itself if it's missing
	
	string srcEntry = "";

	if (!srcHasTrailingSlash) {
		srcEntry = 	srcArg[srcArg.lastIndexOf('/')..$]; // The "/" is included
		dstArg ~= srcEntry ~ "/";
		trace("Definitive dst folder because of lacking trailing / in the source: ", dstArg);
		if (!dstArg.exists) {
			trace("Creating destination folder ", dstArg);
			if (dryRun) {
				info("Dry run: skipping destination folder creation.");
			} else {
				mkdir(dstArg);
			}
		}
	}
	

	if (!dryRun) {
		enforce(dstArg.exists, "The destination directory doesn't exist and can't be created");
	}
	
	// Abort if dst is not a folder at this point.

	DirEntry dst;

	if (!dryRun || dstArg.exists) {
		dst = DirEntry(dstArg);
		enforce(dst.isDir, "The destination is not a directory");
	}
	
	// Gather the list of entries both in src and in dst.
	
	DirEntry[] srcEntries = src.dirEntries(SpanMode.shallow, false).array;
	
	// Bad hack: because of dryRun, we can't be sure it'll exist
	DirEntry[] dstEntries = []; 
	
	if ( (!dryRun) || (dstArg.exists && dstArg.isDir) ) {
		dstEntries = dst.dirEntries(SpanMode.shallow, false).array;
	}

	stdout.flush;
	stderr.flush;
	
	// If needed, delete directories form dst not present in src
	if (mustDelete) {
		// We just want the last entry of the path
		auto sortedDst = dstEntries.map!(a => a.name.split('/')[$-1]).array.sort;
		trace("Sorted shortened destination entries: ", sortedDst);
		auto sortedSrc = srcEntries.map!(a => a.name.split('/')[$-1]).array.sort;
		trace("Sorted shortened source entries: ", sortedSrc);
		auto toDelete = setDifference(sortedDst, sortedSrc);
		trace("Entries to be deleted: ", toDelete);
		foreach (entry ; parallel(toDelete)) {
			auto dstEntry = dst ~ "/" ~ entry;
			if (dryRun) {
				info("[Worker ", taskPool.workerIndex, "] Dry run: not deleting destination entry ", dstEntry);
			} else {
				if (dstEntry.isDir) {
					dstEntry.rmdirRecurse;
				} else {
					dstEntry.remove;
				}
			}
		}
	}
	
	// And now, the real meat
	
	string rsyncPath = executeShell("which rsync").output.chomp;
	info("Found rsync at ", rsyncPath);
	stdout.flush;
	stderr.flush;

	int errCode = 0;
	
	foreach(entry ; parallel(srcEntries)) {
		auto newArgs = args.dup;
		newArgs[0] = rsyncPath;
		if (linkDestArg > 0) {
			newArgs[linkDestArg] ~= srcEntry;
		}
		newArgs[$-2] ~= "/" ~ entry.name.split('/')[$-1];
		newArgs[$-1] ~= srcEntry ~ "/";
		
		info("[Worker ", taskPool.workerIndex, "] Processing folder ", entry);
		trace("[Worker ", taskPool.workerIndex, "] Executing: ", newArgs);
		stdout.flush;
		stderr.flush;
		int ret = spawnProcess(newArgs).wait;
		
		switch(ret) {
			case 0:
				break;
			
			case RSYNC_PARTIAL_TRANSFER: // Partial transfer due to vanished source files
				// Here we return this error *only* if it's the only one
				if (errCode == 0) {
					errCode = RSYNC_PARTIAL_TRANSFER;
				}
				break;
			default:
					 // For any other error codes, we report only the first.
				if (errCode == 0 || errCode == RSYNC_PARTIAL_TRANSFER) {
					errCode = ret;
				}
				break;
		}
		
		trace("[Worker ", taskPool.workerIndex, "] Done.");
		info("[Worker ", taskPool.workerIndex, "] Returned ", ret);
		stdout.flush;
		stderr.flush;
	}
	info("Final return code: ", errCode);
	return errCode;
}
