// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#ifndef _VMAPI_SHARED_H
#define _VMAPI_SHARED_H
#include "smPublic.h"
#include "smapiTableParser.h"
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Shared_Memory_Access_Add_DM
typedef commonOutputFields vmApiSharedMemoryAccessAddDmOutput;

// Parser table for Shared_Memory_Access_Add_DM
static tableLayout Shared_Memory_Access_Add_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiSharedMemoryAccessAddDmOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiSharedMemoryAccessAddDmOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiSharedMemoryAccessAddDmOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiSharedMemoryAccessAddDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smShared_Memory_Access_Add_DM(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, char * memorySegmentName,
		vmApiSharedMemoryAccessAddDmOutput ** outData);

// Shared_Memory_Access_Query_DM
typedef struct _vmApiSharedMemorySegmentName { // Common structure used by Shared_Memory_Access_Query
	char * memorySegmentName;
} vmApiSharedMemorySegmentName;

typedef struct _vmApiSharedMemoryAccessQueryDm {
	commonOutputFields common;
	int memorySegmentNameCount;
	vmApiSharedMemorySegmentName * memorySegmentNameList;
} vmApiSharedMemoryAccessQueryDmOutput;

// Parser table for Shared_Memory_Access_Query_DM
static tableLayout Shared_Memory_Access_Query_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiSharedMemoryAccessQueryDmOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiSharedMemoryAccessQueryDmOutput, common.requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiSharedMemoryAccessQueryDmOutput, common.returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiSharedMemoryAccessQueryDmOutput, common.reasonCode) },

{ APITYPE_ARRAY_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
		vmApiSharedMemoryAccessQueryDmOutput, memorySegmentNameList) },
		{ APITYPE_ARRAY_STRUCT_COUNT, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
				offsetof(vmApiSharedMemoryAccessQueryDmOutput,
						memorySegmentNameCount) }, {
				APITYPE_NOBUFFER_STRUCT_LEN, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
				sizeof(vmApiSharedMemorySegmentName) }, { APITYPE_STRING_LEN,
				1, 8, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
						vmApiSharedMemorySegmentName, memorySegmentName) }, {
				APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

int smShared_Memory_Access_Query_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * memorySegmentName,
		vmApiSharedMemoryAccessQueryDmOutput ** outData);

// Shared_Memory_Access_Remove_DM
typedef commonOutputFields vmApiSharedMemoryAccessRemoveDmOutput;

// Parser table for Shared_Memory_Access_Remove_DM
static tableLayout Shared_Memory_Access_Remove_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiSharedMemoryAccessRemoveDmOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiSharedMemoryAccessRemoveDmOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiSharedMemoryAccessRemoveDmOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiSharedMemoryAccessRemoveDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smShared_Memory_Access_Remove_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * memorySegmentName,
		vmApiSharedMemoryAccessRemoveDmOutput ** outData);

// Shared_Memory_Create
typedef commonOutputFields vmApiSharedMemoryCreateOutput;

// Parser table for Shared_Memory_Create
static tableLayout Shared_Memory_Create_Layout = { { APITYPE_BASE_STRUCT_LEN,
		4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiSharedMemoryCreateOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(vmApiSharedMemoryCreateOutput,
				requestId) }, { APITYPE_INT4, 4, 4, STRUCT_INDX_0,
		NEST_LEVEL_0, offsetof(vmApiSharedMemoryCreateOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiSharedMemoryCreateOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int
		smShared_Memory_Create(struct _VmApiInternalContext* vmapiContextP,
				char * userid, int passwordLength, char * password,
				char * targetIdentifier, char * memorySegmentName,
				unsigned long long beginPage, unsigned long long endPage,
				char pageAccessDescriptor, char memoryAttributes,
				char * memoryAccessIdentifier,
				vmApiSharedMemoryCreateOutput ** outData);

// Shared_Memory_Delete
typedef commonOutputFields vmApiSharedMemoryDeleteOutput;

// Parser table for Shared_Memory_Delete
static tableLayout Shared_Memory_Delete_Layout = { { APITYPE_BASE_STRUCT_LEN,
		4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiSharedMemoryDeleteOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(vmApiSharedMemoryDeleteOutput,
				requestId) }, { APITYPE_INT4, 4, 4, STRUCT_INDX_0,
		NEST_LEVEL_0, offsetof(vmApiSharedMemoryDeleteOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiSharedMemoryDeleteOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smShared_Memory_Delete(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, char * memorySegmentName,
		vmApiSharedMemoryDeleteOutput ** outData);

// Shared_Memory_Query
typedef struct _vmApiSharedPageRangeInfo {
	unsigned long long beginPage;
	unsigned long long endPage;
	char pageAccessDescriptor;
} vmApiSharedPageRangeInfo;

typedef struct _vmApiSharedMemorySegmentInfo {
	char * memorySegmentName;
	char memorySegmentStatus;
	int pageRangeCount;
	vmApiSharedPageRangeInfo * pageRangeList;
} vmApiSharedMemorySegmentInfo;

typedef struct _vmApiSharedMemoryQueryOutput {
	commonOutputFields common;
	int memorySegmentCount;
	vmApiSharedMemorySegmentInfo * memorySegmentInfoList;
} vmApiSharedMemoryQueryOutput;

// Parser table for Shared_Memory_Query
static tableLayout Shared_Memory_Query_Layout = { { APITYPE_BASE_STRUCT_LEN, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, sizeof(vmApiSharedMemoryQueryOutput) },
		{ APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiSharedMemoryQueryOutput, common.requestId) }, {
				APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiSharedMemoryQueryOutput, common.returnCode) }, {
				APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiSharedMemoryQueryOutput, common.reasonCode) },

		{ APITYPE_ARRAY_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiSharedMemoryQueryOutput, memorySegmentInfoList) }, {
				APITYPE_ARRAY_STRUCT_COUNT, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
				offsetof(vmApiSharedMemoryQueryOutput, memorySegmentCount) }, {
				APITYPE_STRUCT_LEN, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
				sizeof(vmApiSharedMemorySegmentInfo) }, { APITYPE_STRING_LEN,
				1, 8, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
						vmApiSharedMemorySegmentInfo, memorySegmentName) }, {
				APITYPE_INT1, 1, 1, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
						vmApiSharedMemorySegmentInfo, memorySegmentStatus) },

		{ APITYPE_ARRAY_LEN, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
				vmApiSharedMemorySegmentInfo, pageRangeList) }, {
				APITYPE_ARRAY_STRUCT_COUNT, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
				offsetof(vmApiSharedMemorySegmentInfo, pageRangeCount) }, {
				APITYPE_STRUCT_LEN, 4, 4, STRUCT_INDX_2, NEST_LEVEL_2,
				sizeof(vmApiSharedPageRangeInfo) }, { APITYPE_INT8, 8, 8,
				STRUCT_INDX_2, NEST_LEVEL_2, offsetof(vmApiSharedPageRangeInfo,
						beginPage) }, { APITYPE_INT8, 8, 8, STRUCT_INDX_2,
				NEST_LEVEL_2, offsetof(vmApiSharedPageRangeInfo, endPage) }, {
				APITYPE_INT1, 1, 1, STRUCT_INDX_2, NEST_LEVEL_2, offsetof(
						vmApiSharedPageRangeInfo, pageAccessDescriptor) },

		{ APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

int smShared_Memory_Query(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, char * memorySegmentName,
		vmApiSharedMemoryQueryOutput ** outData);

// Shared_Memory_Replace
typedef commonOutputFields vmApiSharedMemoryReplaceOutput;

//  Parser table for Shared_Memory_Replace
static tableLayout Shared_Memory_Replace_Layout = { { APITYPE_BASE_STRUCT_LEN,
		4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiSharedMemoryReplaceOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(vmApiSharedMemoryReplaceOutput,
				requestId) }, { APITYPE_INT4, 4, 4, STRUCT_INDX_0,
		NEST_LEVEL_0, offsetof(vmApiSharedMemoryReplaceOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiSharedMemoryReplaceOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smShared_Memory_Replace(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, char * memorySegmentName,
		char * memoryAccessIdentifier,
		vmApiSharedMemoryReplaceOutput ** outData);

#ifdef __cplusplus
}
#endif

#endif
