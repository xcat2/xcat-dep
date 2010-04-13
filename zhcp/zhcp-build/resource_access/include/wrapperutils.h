// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#include <stdio.h>
#include <string.h>
#include "vmapiImage.h"
#include "vmapiVirtual.h"
#include "smPublic.h"
#include "vmapiSystem.h"
#include "vmapiAsynchronous.h"
#include "vmapiAuthorization.h"
#include "vmapiCheckAuthentication.h"
#include "vmapiDirectoryManager.h"
#include "vmapiProfile.h"

void releaseContext(VmApiInternalContext* context);
void initializeContext(VmApiInternalContext* context);
int isImageNameInvalid(char* imageName);
int isDevNumberInvalid(char* devNumber);
void trim(char * s);
