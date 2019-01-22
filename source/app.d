void main(string[] args)
{
	import std.stdio : writeln;
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
	import std.string : startsWith, chomp;
	import std.array : array, split;

	import std.experimental.logger;
	
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
	
	foreach(entry ; parallel(srcEntries)) {
		auto newArgs = args.dup;
		newArgs[0] = rsyncPath;
		string toAdd = "/" ~ entry.name.split('/')[$-1];
		if (linkDestArg > 0) {
			// Add the folder to the --link-dest argument if it existes
			string newLinkDest = newArgs[linkDestArg].findSplitAfter("=")[1] ~ toAdd;
			if (newLinkDest.exists) {
				trace("[Worker ", taskPool.workerIndex, "] Link destination subfolder ", newLinkDest, " exists.");
				newArgs[linkDestArg] ~= toAdd;
			} else {
				trace("[Worker ", taskPool.workerIndex, "] Link destination subfolder ", newLinkDest, " doesn't exist, skipping.");
				newArgs = removeElement(newArgs,linkDestArg);
			}
		}
		newArgs[$-1] ~= "/" ~ entry.name.split('/')[$-1];
		newArgs[$-2] ~= "/" ~ entry.name.split('/')[$-1];
		
		trace("[Worker ", taskPool.workerIndex, "] Executing: ", newArgs);
		spawnProcess(newArgs).wait;
		trace("[Worker ", taskPool.workerIndex, "] Done.");
	}
}
