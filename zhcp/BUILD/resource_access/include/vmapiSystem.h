// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#ifndef _VMAPI_SYSTEM_H
#define _VMAPI_SYSTEM_H
#include "smPublic.h"
#include "smapiTableParser.h"
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// IPaddr_Get
// This is here because it is VM related vs userid related
typedef struct _vmApiIPAddr_GetOutput {
	commonOutputFields common;
	int ipCount;
	vmApiCStringInfo * ipList; // should only be one item in the list
} vmApiIPaddrGetOutput;

// Parser table for  IPaddr_Get
static tableLayout IPaddr_Get_Layout = { { APITYPE_BASE_STRUCT_LEN, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, sizeof(vmApiIPaddrGetOutput) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiIPaddrGetOutput, common.requestId) }, { APITYPE_INT4, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(vmApiIPaddrGetOutput,
				common.returnCode) }, { APITYPE_INT4, 4, 4, STRUCT_INDX_0,
		NEST_LEVEL_0, offsetof(vmApiIPaddrGetOutput, common.reasonCode) },

{ APITYPE_C_STR_ARRAY_PTR, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
		vmApiIPaddrGetOutput, ipList) }, { APITYPE_C_STR_ARRAY_COUNT, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(vmApiIPaddrGetOutput, ipCount) },
		{ APITYPE_C_STR_STRUCT_LEN, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
				sizeof(vmApiCStringInfo) }, { APITYPE_C_STR_PTR, 4, 4,
				STRUCT_INDX_1, NEST_LEVEL_1, offsetof(vmApiCStringInfo,
						vmapiString) },

		{ APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

int smIPaddr_Get(struct _VmApiInternalContext* vmapiContextP,
		vmApiIPaddrGetOutput ** outData);

// System_Info_Query
typedef struct _vmApiSystemInfoQueryOutput {
	commonOutputFields common;
	char * timezone;
	char * time;
	char * vmVersion;
	char * cpGenTime;
	char * cpIplTime;
	char * realStorageSize;
} vmApiSystemInfoQueryOutput;

// Parser table for  Virtual_Network_Query_OSA
static tableLayout System_Info_Query_Layout = { { APITYPE_BASE_STRUCT_LEN, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, sizeof(vmApiSystemInfoQueryOutput) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiSystemInfoQueryOutput, common.requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiSystemInfoQueryOutput, common.returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiSystemInfoQueryOutput, common.reasonCode) },

{ APITYPE_C_STR_PTR, 4, 43, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
		vmApiSystemInfoQueryOutput, timezone) },
		{ APITYPE_C_STR_PTR, 4, 43, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiSystemInfoQueryOutput, time) }, { APITYPE_C_STR_PTR, 4,
				80, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiSystemInfoQueryOutput, vmVersion) }, {
				APITYPE_C_STR_PTR, 4, 43, STRUCT_INDX_0, NEST_LEVEL_0,
				offsetof(vmApiSystemInfoQueryOutput, cpGenTime) }, {
				APITYPE_C_STR_PTR, 4, 43, STRUCT_INDX_0, NEST_LEVEL_0,
				offsetof(vmApiSystemInfoQueryOutput, cpIplTime) }, {
				APITYPE_C_STR_PTR, 4, 80, STRUCT_INDX_0, NEST_LEVEL_0,
				offsetof(vmApiSystemInfoQueryOutput, realStorageSize) },

		{ APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

int smSystem_Info_Query(struct _VmApiInternalContext* vmapiContextP,
		vmApiSystemInfoQueryOutput ** outData);

// System_IO_Query
typedef struct _vmApiSystemIoQueryOutput {
	commonOutputFields common;
	int chipidCount;
	vmApiCStringInfo * chipidList;
} vmApiSystemIoQueryOutput;

// Parser table for  Virtual_Network_Query_OSA
static tableLayout System_IO_Query_Layout = { { APITYPE_BASE_STRUCT_LEN, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, sizeof(vmApiSystemIoQueryOutput) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiSystemIoQueryOutput, common.requestId) }, { APITYPE_INT4,
		4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(vmApiSystemIoQueryOutput,
				common.returnCode) }, { APITYPE_INT4, 4, 4, STRUCT_INDX_0,
		NEST_LEVEL_0, offsetof(vmApiSystemIoQueryOutput, common.reasonCode) },

{ APITYPE_C_STR_ARRAY_PTR, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
		vmApiSystemIoQueryOutput, chipidList) }, { APITYPE_C_STR_ARRAY_COUNT,
		4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(vmApiSystemIoQueryOutput,
				chipidCount) }, { APITYPE_C_STR_STRUCT_LEN, 4, 4,
		STRUCT_INDX_1, NEST_LEVEL_1, sizeof(vmApiCStringInfo) }, {
		APITYPE_C_STR_PTR, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
				vmApiCStringInfo, vmapiString) },

{ APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

int smSystem_IO_Query(struct _VmApiInternalContext* vmapiContextP,
		char * realDeviceAddress, vmApiSystemIoQueryOutput ** outData);

#ifdef __cplusplus
}
#endif

#endif
