// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "wrapperutils.h"

/**
 * Replace specified user directory entry.
 *
 * @param $1: Name of the z/VM guest to replace the directory entry
 * @param $2: Text file containing the new directory entry
 *
 * @return 0 If directory entry was successfully replaced
 *         1 If given invalid parameters
 *         2 If directory entry replace failed
 */
int main(int argC, char* argV[]) {

	if (argC != 3) {
		printf("Error: Wrong number of parameters\n");
		return 1;
	}

	// Get user name
	char* image = argV[1];
	char* file = argV[2];

	// Check if the userID is between 1 and 8 characters
	if (isImageNameInvalid(image))
		return 1;

	VmApiInternalContext context;

	// Initialize context
	extern struct _smTrace externSmapiTraceFlags;
	smMemoryGroupContext memContext;
	memset(&context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));
	context.smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context.memContext = &memContext;

	// Lock user directory entry
	int rc = lockImage(image, &context);

	FILE * userDirEntry;

	// Open file for user directory entry
	userDirEntry = fopen(file, "r");
	if (userDirEntry == NULL)
		printf("Error: Failed to open %s\n", file);
	else {
		// Read in user directory entry
		int recordCount = 0;
		int i = 0;
		char line[100], buffer[30][100];
		char * ptr;
		while (!feof(userDirEntry)) {
			// Read in 100 characters
			fgets(line, 100, userDirEntry);

			// Delete new line
			ptr = strstr(line, "\n");
			if (ptr != NULL) {
				strncpy(ptr, "\0", 1);
			}

			// Copy line into buffer
			strcpy(buffer[i], line);
			i++;

			if (!feof(userDirEntry))
				recordCount++;
		}

		// Close user directory entry
		fclose(userDirEntry);

		// Create image record
		vmApiImageRecord record[recordCount];

		// Copy buffer contents into image record
		for (i = 0; i < recordCount; i++) {
			record[i].imageRecordLength = strlen(buffer[i]);
			record[i].imageRecord = buffer[i];
		}

		// Replace user directory entry
		rc = replaceImage(image, &context, &record, recordCount);
	}

	// Release context
	smMemoryGroupFreeAll(&context);
	smMemoryGroupTerminate(&context);

	return rc;
}

/**
 * Lock specified user directory entry.
 *
 * @param $1: Name of the z/VM guest directory entry to lock
 *
 * @return 0 If directory entry was successfully locked
 *         1 If given invalid parameters
 *         2 If directory entry lock failed
 */
int lockImage(char * image, VmApiInternalContext context) {
	printf("Locking %s... ", image);

	vmApiImageLockDmOutput * lockOutput;
	int rc = smImage_Lock_DM(&context, "", // Authorizing user
			0, // Password length
			"", // Password
			image, // Image name
			"", // Device virtual address
			&lockOutput);

	if (rc || (lockOutput->returnCode && lockOutput->returnCode != 400
			|| (lockOutput->reasonCode && lockOutput->reasonCode != 12))) {
		printf("Failed\n");

		rc ? printf("  Return Code: %d\n", rc) : printf("  Return Code: %d\n"
			"  Reason Code: %d\n", lockOutput->returnCode,
				lockOutput->reasonCode);

		return 2;
	} else {
		printf("Done\n");
		return 0;
	}
}

/**
 * Unlock specified user directory entry.
 *
 * @param $1: Name of the z/VM guest directory entry to unlock
 *
 * @return 0 If directory entry was successfully unlocked
 *         1 If given invalid parameters
 *         2 If directory entry unlock failed
 */
int unlockImage(char * image, VmApiInternalContext context) {
	printf("Unlocking %s... ", image);

	vmApiImageUnlockDmOutput * unlockOutput;
	int rc = smImage_Unlock_DM(&context, "", // Authorizing user
			0, // Password length
			"", // Password
			image, // Image name
			"", // Device virtual address
			&unlockOutput);

	if (rc || unlockOutput->returnCode || unlockOutput->reasonCode) {
		printf("Failed\n");

		rc ? printf("  Return Code: %d\n", rc) : printf("  Return Code: %d\n"
			"  Reason Code: %d\n", unlockOutput->returnCode,
				unlockOutput->reasonCode);

		return 2;
	} else {
		printf("Done\n");
		return 0;
	}
}

/**
 * Replace specified user directory entry.
 *
 * @param $1: Name of the z/VM guest to replace the directory entry
 *
 * @return 0 If directory entry was successfully unlocked
 *         1 If given invalid parameters
 *         2 If directory entry unlock failed
 */
int replaceImage(char * image, VmApiInternalContext context,
		vmApiImageRecord * record, int recordCount) {
	printf("Replacing directory entry of %s... ", image);

	vmApiImageReplaceDmOutput* replaceOutput;
	int rc = smImage_Replace_DM(&context, "", // Authorizing user
			0, // Password length
			"", // Password
			image, // Image name
			recordCount, // Record count
			record, // Record array
			&replaceOutput);

	if (rc || replaceOutput->returnCode || replaceOutput->reasonCode) {
		printf("Failed\n");

		rc ? printf("  Return Code: %d\n", rc) : printf("  Return Code: %d\n"
			"  Reason Code: %d\n", replaceOutput->returnCode,
				replaceOutput->reasonCode);

		// Unlock user directory entry
		rc = unlockImage(image, context);
		return 2;
	} else {
		printf("Done\n");
		return 0;
	}
}
