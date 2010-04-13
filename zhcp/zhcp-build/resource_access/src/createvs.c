// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "wrapperutils.h"

/**
 * Creates a z/VM guest with the specified name.
 *
 * @param $1: The name of the guest which is to be created
 *
 * @return 0 If the virtual image now exists
 *         1 If given invalid parameters
 *         2 If image creation failed
 */
int main(int argC, char * argV[]) {

	// Should be only 1 or 2 arguments
	if (argC < 2 || argC > 3) {
		printf("Error: Wrong number of parameters\n");
		return 1;
	}

	// Get image name
	char * imageName = argV[1];

	// Check if image name is between 1 and 8 characters
	if (isImageNameInvalid(imageName))
		return 1;

	printf("Creating user directory entry for %s... ", imageName);

	// Create DirMaint directory entry
	int rc;
	if (argC == 3) {
		rc = createUsingFile(imageName, argV[2]);
	}
	// If no user directory entry is given, create a NOLOG userID
	else {
		rc = createNoLog(imageName);
	}

	return rc;
}

/**
 * Creates a z/VM guest with the specified name using a directory entry file.
 *
 * @param $1: The name of the guest which is to be created
 * @param $2: The directory entry in a file
 *
 * @return 0 If the virtual image now exists
 *         1 If given invalid parameters
 *         2 If image creation failed
 */
int createUsingFile(char * imageName, char * file) {
	VmApiInternalContext context;

	// Initialize context
	extern struct _smTrace externSmapiTraceFlags;
	smMemoryGroupContext memContext;
	memset(&context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));
	context.smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context.memContext = &memContext;

	vmApiImageCreateDmOutput * output;

	int rc;
	FILE * userProfile;

	// Open file for user directory entry
	userProfile = fopen(file, "r");
	if (userProfile == NULL)
		printf("  Error: Failed to open %s\n", file);
	else {
		// Read in user directory entry
		int recordCount = 0, i = 0;
		char line[100], buffer[30][100];
		char * ptr;
		while (!feof(userProfile)) {
			// Read in 100 characters
			fgets(line, 100, userProfile);

			// Delete new line
			ptr = strstr(line, "\n");
			if (ptr != NULL) {
				strncpy(ptr, "\0", 1);
			}

			// Copy line into buffer
			strcpy(buffer[i], line);
			i++;

			if (!feof(userProfile))
				recordCount++;
		}

		// Check USER line for correct virtual server name
		ptr = strstr(buffer[0], imageName);
		char newLine[100];
		// If the virtual server name is NOT in the USER line
		if (ptr == NULL) {
			// Insert virtual server name into the USER line
			ptr = strtok(buffer[0], " ");

			int i = 0;
			while (ptr != NULL) {
				if (i == 1) {
					strcat(newLine, imageName);
				} else {
					strcat(newLine, ptr);
				}
				strcat(newLine, " ");
				ptr = strtok(NULL, " ");
				i++;
			}

			strcpy(buffer[0], newLine);
		}

		// Create image record
		vmApiImageRecord record[recordCount];
		// Copy buffer contents into image record
		for (i = 0; i < recordCount; i++) {
			record[i].imageRecordLength = strlen(buffer[i]);
			record[i].imageRecord = buffer[i];
		}

		// Close user directory entry
		fclose(userProfile);

		rc = smImage_Create_DM(&context, "", 0, "", // Authorizing user, password length, password.
				imageName, // Image name.
				"", // The prototype to use for creating the image.
				0, "", // Initial password length, initial password.
				"", recordCount, // Initial account number, image record array length
				&record, // Image record.
				&output);
	}

	if (rc || (output->common.returnCode && output->common.returnCode != 400
			&& output->common.returnCode != 592)
			|| (output->common.reasonCode && output->common.reasonCode != 8
					&& output->common.reasonCode != 0)) {
		printf("Failed\n");

		rc ? printf("  Return Code: %d\n", rc) : printf("  Return Code: %d\n"
			"  Reason Code: %d\n", output->common.returnCode,
				output->common.reasonCode);

		// Release context
		smMemoryGroupFreeAll(&context);
		smMemoryGroupTerminate(&context);

		return 2;
	}

	printf("Done\n");

	// Release context
	smMemoryGroupFreeAll(&context);
	smMemoryGroupTerminate(&context);

	return 0;
}

/**
 * Creates a z/VM guest with the specified name with NOLOG.
 *
 * @param $1: The name of the guest which is to be created
 *
 * @return 0 If the virtual image now exists
 *         1 If given invalid parameters
 *         2 If image creation failed
 */
int createNoLog(char * imageName) {
	VmApiInternalContext context;

	// Initialize context
	extern struct _smTrace externSmapiTraceFlags;
	smMemoryGroupContext memContext;
	memset(&context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));
	context.smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context.memContext = &memContext;

	vmApiImageCreateDmOutput * output;

	int rc;
	char userLine[19] = "USER ";
	strcat(userLine, imageName);
	strcat(userLine, " NOLOG");

	vmApiImageRecord record;
	record.imageRecordLength = 19; // Length of image_record
	record.imageRecord = userLine; // The user or profile entry

	rc = smImage_Create_DM(&context, "", 0, "", // Authorizing user, password length, password.
			imageName, // Image name.
			"", // The prototype to use for creating the image.
			0, "", // Initial password length, initial password.
			"", 1, // Initial account number, image record array length
			&record, // Image record.
			&output);

	if (rc || (output->common.returnCode && output->common.returnCode != 400
			&& output->common.returnCode != 592)
			|| (output->common.reasonCode && output->common.reasonCode != 8
					&& output->common.reasonCode != 0)) {
		printf("Failed\n");

		rc ? printf("  Return Code: %d\n", rc) : printf("  Return Code: %d\n"
			"  Reason Code: %d\n", output->common.returnCode,
				output->common.reasonCode);

		// Release context
		smMemoryGroupFreeAll(&context);
		smMemoryGroupTerminate(&context);

		return 2;
	} else {
		printf("Done\n");

		// Release context
		smMemoryGroupFreeAll(&context);
		smMemoryGroupTerminate(&context);

		return 0;
	}
}
