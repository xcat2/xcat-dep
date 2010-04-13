// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#ifndef _SMSOCKET_H
#define _SMSOCKET_H
#include "smPublic.h"

int smSocketInitialize(struct _VmApiInternalContext* vmapiContextP,
		int * sockId);
int smSocketWrite(struct _VmApiInternalContext* vmapiContextP, int sockId,
		char * data, int dataLen);
int smSocketRead(struct _VmApiInternalContext* vmapiContextP, int sockId,
		char * buff, int len);
int smSocketReadLoop(struct _VmApiInternalContext* vmapiContextP, int sockId,
		char * buff, int len);
int smSocketTerminate(struct _VmApiInternalContext* vmapiContextP, int sockId);
#endif
