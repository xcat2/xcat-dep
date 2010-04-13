// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include "wrapperutils.h"

/**
 * @see wrapperutils.h: releaseContext
 */
void releaseContext(VmApiInternalContext* context) {
	smMemoryGroupFreeAll(context);
	smMemoryGroupTerminate(context);
}

/**
 * @see wrapperutils.h getContext
 */
void initializeContext(VmApiInternalContext* context) {

	extern struct _smTrace externSmapiTraceFlags;

	smMemoryGroupContext memContext;

	memset(context, 0, sizeof(context));
	memset(&memContext, 0, sizeof(memContext));
	memset(&externSmapiTraceFlags, 0, sizeof(smTrace));

	context->smTraceDetails = (struct _smTrace *) &externSmapiTraceFlags;
	context->memContext = &memContext;

	smMemoryGroupInitialize(context);
}

/**
 * Check if image name is between 1 and 8 characters
 */
int isImageNameInvalid(char* imageName) {

	if (strlen(imageName) < 1 || strlen(imageName) > 8) {
		printf("  User ID must be between 1 and 8 characters in length.\n"
			"Operation Failed\n");
		return 1;
	} else {
		return 0;
	}
}

/**
 * Check if device addresses are specified as 4-digit hexadecimal numbers
 */
int isDevNumberInvalid(char* devNumber) {

	if ((strlen(devNumber) == 4) && ((devNumber[0] > 47 && devNumber[0] < 58)
			|| (devNumber[0] > 65 && devNumber[0] < 71) || (devNumber[0] > 97
			&& devNumber[0] < 103))
			&& ((devNumber[1] > 47 && devNumber[1] < 58) || (devNumber[1] > 65
					&& devNumber[1] < 71) || (devNumber[1] > 97 && devNumber[1]
					< 103)) && ((devNumber[2] > 47 && devNumber[2] < 58)
			|| (devNumber[2] > 65 && devNumber[2] < 71) || (devNumber[2] > 97
			&& devNumber[2] < 103))
			&& ((devNumber[3] > 47 && devNumber[3] < 58) || (devNumber[3] > 65
					&& devNumber[3] < 71) || (devNumber[3] > 97 && devNumber[3]
					< 103))) {
		return 0;
	} else {
		printf(
				"  Device addresses must be specified as 4-digit hexadecimal numbers.\n"
					"Operation Failed\n");
		return 1;
	}
}

/**
 * Trim a specified string
 */
void trim(char * s) {
	// Length of specified string
	int len = strlen(s);
	int end = len - 1;
	int start = 0;
	int i = 0;

	// Find non-blank space from left
	while ((start < len) && (s[start] <= ' ')) {
		start++;
	}

	// Find non-blank space from right
	while ((start < end) && (s[end] <= ' ')) {
		end--;
	}

	if (start > end) {
		memset(s, '\0', len);
		return;
	}

	for (i = 0; (i + start) <= end; i++) {
		s[i] = s[start + i];
	}

	// Trim string
	memset((s + i), '\0', len - i);
}
