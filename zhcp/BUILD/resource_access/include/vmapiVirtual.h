// IBM (C) Copyright 2010 Eclipse Public License
// http://www.eclipse.org/org/documents/epl-v10.html
#ifndef _VMAPI_VIRTUAL_H
#define _VMAPI_VIRTUAL_H
#include "smPublic.h"
#include "smapiTableParser.h"
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Virtual_Channel_Connection_Create
typedef commonOutputFields vmApiVirtualChannelConnectionCreateOutput;

// Parser table for Virtual_Channel_Connection_Create
static tableLayout Virtual_Channel_Connection_Create_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualChannelConnectionCreateOutput) }, { APITYPE_INT4, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualChannelConnectionCreateOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualChannelConnectionCreateOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualChannelConnectionCreateOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smVirtual_Channel_Connection_Create(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * imageDeviceNumber, char * coupledImageName,
		char * coupledImageDeviceNumber,
		vmApiVirtualChannelConnectionCreateOutput ** outData);

// Virtual_Channel_Connection_Create_DM
typedef commonOutputFields vmApiVirtualChannelConnectionCreateDmOutput;

//  Parser table for Virtual_Channel_Connection_Create_DM
static tableLayout Virtual_Channel_Connection_Create_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualChannelConnectionCreateDmOutput) }, { APITYPE_INT4,
		4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualChannelConnectionCreateDmOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualChannelConnectionCreateDmOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualChannelConnectionCreateDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smVirtual_Channel_Connection_Create_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * imageDeviceNumber, char * coupledImageName,
		vmApiVirtualChannelConnectionCreateDmOutput ** outData);

// Virtual_Channel_Connection_Delete
typedef commonOutputFields vmApiVirtualChannelConnectionDeleteOutput;

// Parser table for Virtual_Memory_Access_Add_DM
static tableLayout Virtual_Channel_Connection_Delete_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualChannelConnectionDeleteOutput) }, { APITYPE_INT4, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualChannelConnectionDeleteOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualChannelConnectionDeleteOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualChannelConnectionDeleteOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smVirtual_Channel_Connection_Delete(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * imageDeviceNumber,
		vmApiVirtualChannelConnectionDeleteOutput ** outData);

// Virtual_Channel_Connection_Delete_DM
typedef commonOutputFields vmApiVirtualChannelConnectionDeleteDmOutput;

// Parser table for Virtual_Channel_Connection_Delete_DM
static tableLayout Virtual_Channel_Connection_Delete_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualChannelConnectionDeleteDmOutput) }, { APITYPE_INT4,
		4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualChannelConnectionDeleteDmOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualChannelConnectionDeleteDmOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualChannelConnectionDeleteDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smVirtual_Channel_Connection_Delete_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * imageDeviceNumber,
		vmApiVirtualChannelConnectionDeleteDmOutput ** outData);

// Virtual_Network_Adapter_Connect_LAN
typedef commonOutputFields vmApiVirtualNetworkAdapterConnectLanOutput;

// Parser table for Virtual_Network_Adapter_Connect_LAN
static tableLayout Virtual_Network_Adapter_Connect_LAN_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkAdapterConnectLanOutput) }, { APITYPE_INT4,
		4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterConnectLanOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterConnectLanOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterConnectLanOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smVirtual_Network_Adapter_Connect_LAN(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * imageDeviceNumber, char * lanName, char * lanOwner,
		vmApiVirtualNetworkAdapterConnectLanOutput ** outData);

// Virtual_Network_Adapter_Connect_LAN_DM
typedef commonOutputFields vmApiVirtualNetworkAdapterConnectLanDmOutput;

// Parser table for Virtual_Network_Adapter_Connect_LAN_DM
static tableLayout Virtual_Network_Adapter_Connect_LAN_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkAdapterConnectLanDmOutput) }, { APITYPE_INT4,
		4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterConnectLanDmOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterConnectLanDmOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterConnectLanDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smVirtual_Network_Adapter_Connect_LAN_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * imageDeviceNumber, char * lanName, char * lanOwner,
		vmApiVirtualNetworkAdapterConnectLanDmOutput ** outData);

// Virtual_Network_Adapter_Connect_Vswitch
typedef commonOutputFields vmApiVirtualNetworkAdapterConnectVswitchOutput;

// Parser table for Virtual_Network_Adapter_Connect_Vswitch
static tableLayout Virtual_Network_Adapter_Connect_Vswitch_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkAdapterConnectVswitchOutput) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterConnectVswitchOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterConnectVswitchOutput, returnCode) },
		{ APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterConnectVswitchOutput, reasonCode) },
		{ APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smVirtual_Network_Adapter_Connect_Vswitch(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * imageDeviceNumber, char * switchName,
		vmApiVirtualNetworkAdapterConnectVswitchOutput ** outData);

// Virtual_Network_Adapter_Connect_Vswitch_DM
typedef commonOutputFields vmApiVirtualNetworkAdapterConnectVswitchDmOutput;

// Parser table for Virtual_Network_Adapter_Connect_Vswitch_DM
static tableLayout
		Virtual_Network_Adapter_Connect_Vswitch_DM_Layout = { {
				APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
				sizeof(vmApiVirtualNetworkAdapterConnectVswitchDmOutput) }, {
				APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
						vmApiVirtualNetworkAdapterConnectVswitchDmOutput,
						requestId) }, { APITYPE_INT4, 4, 4, STRUCT_INDX_0,
				NEST_LEVEL_0, offsetof(
						vmApiVirtualNetworkAdapterConnectVswitchDmOutput,
						returnCode) }, { APITYPE_INT4, 4, 4, STRUCT_INDX_0,
				NEST_LEVEL_0, offsetof(
						vmApiVirtualNetworkAdapterConnectVswitchDmOutput,
						reasonCode) }, { APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smVirtual_Network_Adapter_Connect_Vswitch_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * imageDeviceNumber, char * switchName,
		vmApiVirtualNetworkAdapterConnectVswitchDmOutput ** outData);

// Virtual_Network_Adapter_Create
typedef commonOutputFields vmApiVirtualNetworkAdapterCreateOutput;

// Parser table for Virtual_Network_Adapter_Create
static tableLayout Virtual_Network_Adapter_Create_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkAdapterCreateOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterCreateOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterCreateOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterCreateOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int
		smVirtual_Network_Adapter_Create(
				struct _VmApiInternalContext* vmapiContextP, char * userid,
				int passwordLength, char * password, char * targetIdentifier,
				char * imageDeviceNumber, char adapterType,
				int networkAdapterDevices, char * channelPathId,
				vmApiVirtualNetworkAdapterCreateOutput ** outData);

// Virtual_Network_Adapter_Create_DM
typedef commonOutputFields vmApiVirtualNetworkAdapterCreateDmOutput;

// Parser table for Virtual_Network_Adapter_Create_DM
static tableLayout Virtual_Network_Adapter_Create_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkAdapterCreateDmOutput) }, { APITYPE_INT4, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterCreateDmOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterCreateDmOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterCreateDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smVirtual_Network_Adapter_Create_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * imageDeviceNumber, char adapterType, int networkAdapterDevices,
		char * channelPathId, char * macId,
		vmApiVirtualNetworkAdapterCreateDmOutput ** outData);

// Virtual_Network_Adapter_Delete
typedef commonOutputFields vmApiVirtualNetworkAdapterDeleteOutput;

// Parser table for Virtual_Network_Adapter_Delete
static tableLayout Virtual_Network_Adapter_Delete_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkAdapterDeleteOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterDeleteOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterDeleteOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterDeleteOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smVirtual_Network_Adapter_Delete(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * imageDeviceNumber,
		vmApiVirtualNetworkAdapterDeleteOutput ** outData);

// Virtual_Network_Adapter_Delete_DM
typedef commonOutputFields vmApiVirtualNetworkAdapterDeleteDmOutput;

// Parser table for Virtual_Network_Adapter_Delete_DM
static tableLayout Virtual_Network_Adapter_Delete_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkAdapterDeleteDmOutput) }, { APITYPE_INT4, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterDeleteDmOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterDeleteDmOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterDeleteDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smVirtual_Network_Adapter_Delete_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * imageDeviceNumber,
		vmApiVirtualNetworkAdapterDeleteDmOutput ** outData);

// Virtual_Network_Adapter_Disconnect
typedef commonOutputFields vmApiVirtualNetworkAdapterDisconnectOutput;

// Parser table for Virtual_Network_Adapter_Disconnect
static tableLayout Virtual_Network_Adapter_Disconnect_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkAdapterDisconnectOutput) }, { APITYPE_INT4,
		4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterDisconnectOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterDisconnectOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterDisconnectOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smVirtual_Network_Adapter_Disconnect(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * imageDeviceNumber,
		vmApiVirtualNetworkAdapterDisconnectOutput ** outData);

// Virtual_Network_Adapter_Disconnect_DM
typedef commonOutputFields vmApiVirtualNetworkAdapterDisconnectDmOutput;

//  Parser table for Virtual_Network_Adapter_Disconnect_DM
static tableLayout Virtual_Network_Adapter_Disconnect_DM_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkAdapterDisconnectDmOutput) }, { APITYPE_INT4,
		4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterDisconnectDmOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterDisconnectDmOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterDisconnectDmOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smVirtual_Network_Adapter_Disconnect_DM(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * imageDeviceNumber,
		vmApiVirtualNetworkAdapterDisconnectDmOutput ** outData);

// Virtual_Network_Adapter_Query
typedef struct _vmApiVirtualNetworkAdapter {
	char * imageDeviceNumber;
	char adapterType;
	int networkAdapterDevices;
	char adapterStatus;
	char * lanOwner;
	char * lanName;
} vmApiVirtualNetworkAdapter;

typedef struct _vmApiVirtualNetworkAdapterQueryOutput {
	commonOutputFields common;
	int adapterArrayCount;
	vmApiVirtualNetworkAdapter * adapterList;
} vmApiVirtualNetworkAdapterQueryOutput;

int smVirtual_Network_Adapter_Query(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * imageDeviceNumber,
		vmApiVirtualNetworkAdapterQueryOutput ** outData);

// Parser table for Virtual_Network_Adapter_Query
static tableLayout Virtual_Network_Adapter_Query_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkAdapterQueryOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterQueryOutput, common.requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterQueryOutput, common.returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkAdapterQueryOutput, common.reasonCode) },

{ APITYPE_ARRAY_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
		vmApiVirtualNetworkAdapterQueryOutput, adapterList) }, {
		APITYPE_ARRAY_STRUCT_COUNT, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		offsetof(vmApiVirtualNetworkAdapterQueryOutput, adapterArrayCount) }, {
		APITYPE_STRUCT_LEN, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
		sizeof(vmApiVirtualNetworkAdapter) }, { APITYPE_STRING_LEN, 1, 4,
		STRUCT_INDX_1, NEST_LEVEL_1, offsetof(vmApiVirtualNetworkAdapter,
				imageDeviceNumber) }, { APITYPE_INT1, 1, 1, STRUCT_INDX_1,
		NEST_LEVEL_1, offsetof(vmApiVirtualNetworkAdapter, adapterType) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
				vmApiVirtualNetworkAdapter, networkAdapterDevices) }, {
		APITYPE_INT1, 1, 1, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
				vmApiVirtualNetworkAdapter, adapterStatus) }, {
		APITYPE_STRING_LEN, 0, 8, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
				vmApiVirtualNetworkAdapter, lanOwner) }, { APITYPE_STRING_LEN,
		0, 8, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(vmApiVirtualNetworkAdapter,
				lanName) }, { APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

// Virtual_Network_LAN_Access
typedef commonOutputFields vmApiVirtualNetworkLanAccessOutput;

// Parser table for Virtual_Network_LAN_Access
static tableLayout Virtual_Network_LAN_Access_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkLanAccessOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkLanAccessOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkLanAccessOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkLanAccessOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smVirtual_Network_LAN_Access(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, char * lanName, char * lanOwner,
		char * accessOption, char * accessGrantName, char * promiscuity,
		vmApiVirtualNetworkLanAccessOutput ** outData);

// Virtual_Network_LAN_Access_Query
typedef struct _vmApiVirtualNetworkLanAccessQueryOutput {
	commonOutputFields common;
	int lanAccessCount;
	vmApiCStringInfo * lanAccessList;
} vmApiVirtualNetworkLanAccessQueryOutput;

// Parser table for  Virtual_Network_LANAccess_Query
static tableLayout Virtual_Network_LAN_Access_Query_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkLanAccessQueryOutput) }, { APITYPE_INT4, 4,
		4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkLanAccessQueryOutput, common.requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkLanAccessQueryOutput, common.returnCode) },
		{ APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkLanAccessQueryOutput, common.reasonCode) },

		{ APITYPE_C_STR_ARRAY_PTR, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkLanAccessQueryOutput, lanAccessList) }, {
				APITYPE_C_STR_ARRAY_COUNT, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
				offsetof(vmApiVirtualNetworkLanAccessQueryOutput,
						lanAccessCount) }, { APITYPE_C_STR_STRUCT_LEN, 4, 4,
				STRUCT_INDX_1, NEST_LEVEL_1, sizeof(vmApiCStringInfo) }, {
				APITYPE_C_STR_PTR, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
						vmApiCStringInfo, vmapiString) }, {
				APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

int smVirtual_Network_LAN_Access_Query(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * lanName, char * lanOwner,
		vmApiVirtualNetworkLanAccessQueryOutput ** outData);

// Virtual_Network_LAN_Create
typedef commonOutputFields vmApiVirtualNetworkLanCreateOutput;

// Parser table for Virtual_Network_LAN_Create
static tableLayout Virtual_Network_LAN_Create_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkLanCreateOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkLanCreateOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkLanCreateOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkLanCreateOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smVirtual_Network_LAN_Create(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, char * lanName, char * lanOwner, char lanType,//1,2,3,4
		char transportType, vmApiVirtualNetworkLanCreateOutput ** outData);

// Virtual_Network_LAN_Delete
typedef commonOutputFields vmApiVirtualNetworkLanDeleteOutput;

// Parser table for Virtual_Network_LAN_Delete
static tableLayout Virtual_Network_LAN_Delete_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkLanDeleteOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkLanDeleteOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkLanDeleteOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkLanDeleteOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smVirtual_Network_LAN_Delete(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, char * lanName, char * lanOwner,
		vmApiVirtualNetworkLanDeleteOutput ** outData);

// Virtual_Network_LAN_Query
typedef struct _vmApiVirtualNetworkConnectedAdapterInfo { // Common structure with Virtual Network Vswitch Query
	char * adapterOwner;
	char * imageDeviceNumber;
} vmApiVirtualNetworkConnectedAdapterInfo;

typedef struct _vmApiVirtualNetworkLanInfo {
	char * lanName;
	char * lanOwner;
	char lanType;
	int connectedAdapterCount;
	vmApiVirtualNetworkConnectedAdapterInfo * connectedAdapterList;
} vmApiVirtualNetworkLanInfo;

typedef struct _vmApiVirtualNetworkLanQueryOutput {
	commonOutputFields common;
	int lanCount;
	vmApiVirtualNetworkLanInfo * lanList;
} vmApiVirtualNetworkLanQueryOutput;

// Parser table for  Virtual_Network_LAN_Query
static tableLayout Virtual_Network_LAN_Query_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkLanQueryOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkLanQueryOutput, common.requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkLanQueryOutput, common.returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkLanQueryOutput, common.reasonCode) },

{ APITYPE_ARRAY_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
		vmApiVirtualNetworkLanQueryOutput, lanList) }, {
		APITYPE_ARRAY_STRUCT_COUNT, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		offsetof(vmApiVirtualNetworkLanQueryOutput, lanCount) }, {
		APITYPE_STRUCT_LEN, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
		sizeof(vmApiVirtualNetworkLanInfo) }, { APITYPE_STRING_LEN, 1, 8,
		STRUCT_INDX_1, NEST_LEVEL_1, offsetof(vmApiVirtualNetworkLanInfo,
				lanName) }, { APITYPE_STRING_LEN, 1, 8, STRUCT_INDX_1,
		NEST_LEVEL_1, offsetof(vmApiVirtualNetworkLanInfo, lanOwner) }, {
		APITYPE_INT1, 1, 1, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
				vmApiVirtualNetworkLanInfo, lanType) },

{ APITYPE_ARRAY_LEN, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
		vmApiVirtualNetworkLanInfo, connectedAdapterList) }, {
		APITYPE_ARRAY_STRUCT_COUNT, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
		offsetof(vmApiVirtualNetworkLanInfo, connectedAdapterCount) }, {
		APITYPE_STRUCT_LEN, 4, 4, STRUCT_INDX_2, NEST_LEVEL_2,
		sizeof(vmApiVirtualNetworkConnectedAdapterInfo) }, {
		APITYPE_STRING_LEN, 1, 8, STRUCT_INDX_2, NEST_LEVEL_2, offsetof(
				vmApiVirtualNetworkConnectedAdapterInfo, adapterOwner) }, {
		APITYPE_STRING_LEN, 1, 4, STRUCT_INDX_2, NEST_LEVEL_2, offsetof(
				vmApiVirtualNetworkConnectedAdapterInfo, imageDeviceNumber) },
		{ APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

int smVirtual_Network_LAN_Query(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, char * lanName, char * lanOwner,
		vmApiVirtualNetworkLanQueryOutput ** outData);

// Virtual_Network_Query_LAN
typedef struct _vmApiVirtualNetworkQueryLanOutput {
	commonOutputFields common;
	int lanCount;
	vmApiCStringInfo * lanList;
} vmApiVirtualNetworkQueryLanOutput;

// Parser table for  Virtual_Network_Query_LAN
static tableLayout Virtual_Network_Query_LAN_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkQueryLanOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkQueryLanOutput, common.requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkQueryLanOutput, common.returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkQueryLanOutput, common.reasonCode) },

{ APITYPE_C_STR_ARRAY_PTR, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
		vmApiVirtualNetworkQueryLanOutput, lanList) }, {
		APITYPE_C_STR_ARRAY_COUNT, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkQueryLanOutput, lanCount) }, {
		APITYPE_C_STR_STRUCT_LEN, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
		sizeof(vmApiCStringInfo) }, { APITYPE_C_STR_PTR, 4, 4, STRUCT_INDX_1,
		NEST_LEVEL_1, offsetof(vmApiCStringInfo, vmapiString) },

{ APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

int smVirtual_Network_Query_LAN(struct _VmApiInternalContext* vmapiContextP,
		vmApiVirtualNetworkQueryLanOutput ** outData);

// Virtual_Network_Query_OSA
typedef struct _vmApiVirtualNetworkQueryOsaOutput {
	commonOutputFields common;
	int osaCount;
	vmApiCStringInfo * osaList;
} vmApiVirtualNetworkQueryOsaOutput;

// Parser table for  Virtual_Network_Query_OSA
static tableLayout Virtual_Network_Query_OSA_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkQueryOsaOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkQueryOsaOutput, common.requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkQueryOsaOutput, common.returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkQueryOsaOutput, common.reasonCode) },

{ APITYPE_C_STR_ARRAY_PTR, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
		vmApiVirtualNetworkQueryOsaOutput, osaList) }, {
		APITYPE_C_STR_ARRAY_COUNT, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkQueryOsaOutput, osaCount) }, {
		APITYPE_C_STR_STRUCT_LEN, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
		sizeof(vmApiCStringInfo) }, { APITYPE_C_STR_PTR, 4, 4, STRUCT_INDX_1,
		NEST_LEVEL_1, offsetof(vmApiCStringInfo, vmapiString) },

{ APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

int smVirtual_Network_Query_OSA(struct _VmApiInternalContext* vmapiContextP,
		vmApiVirtualNetworkQueryOsaOutput ** outData);

// Virtual_Network_Vswitch_Create
typedef commonOutputFields vmApiVirtualNetworkVswitchCreateOutput;

// Parser table for Virtual_Network_Vswitch_Create
static tableLayout Virtual_Network_Vswitch_Create_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkVswitchCreateOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkVswitchCreateOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkVswitchCreateOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkVswitchCreateOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smVirtual_Network_Vswitch_Create(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * switchName, char * realDeviceAddress, char * portName,
		char * controllerName, char connectionValue, int queueMemoryLimit,
		char routingValue, char transportType, int vlanId, char portType,
		char updateSystemConfigIndicator, char * systemConfigName,
		char * systemConfigType, char * parmDiskOwner, char * parmDiskNumber,
		char * parmDiskPassword, char * altSystemConfigName,
		char * altSystemConfigType, char * altParmDiskOwner,
		char * altParmDiskNumber, char * altParmDiskPassword, char gvrpValue,
		int nativeVlanId, vmApiVirtualNetworkVswitchCreateOutput ** outData);

// Virtual_Network_Vswitch_Delete
typedef commonOutputFields vmApiVirtualNetworkVswitchDeleteOutput;

// Parser table for Virtual_Network_Vswitch_Delete
static tableLayout Virtual_Network_Vswitch_Delete_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkVswitchDeleteOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkVswitchDeleteOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkVswitchDeleteOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkVswitchDeleteOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smVirtual_Network_Vswitch_Delete(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * switchName, char updateSystemConfigIndicator,
		char * systemConfigName, char * systemConfigType, char * parmDiskOwner,
		char * parmDiskNumber, char * parmDiskPassword,
		char * altSystemConfigName, char * altSystemConfigType,
		char * altParmDiskOwner, char * altParmDiskNumber,
		char * altParmDiskPassword,
		vmApiVirtualNetworkVswitchDeleteOutput ** outData);

// Virtual_Network_Vswitch_Query
typedef struct _vmApiConnectedAdapterInfo {
	int userVlanId;
} vmApiVlanInfo;

typedef struct _vmApiAuthorizedUserInfo {
	char * grantUserid;
	int vlanCount;
	vmApiVlanInfo * vlanList;
} vmApiAuthorizedUserInfo;

typedef struct _vmApiRealDeviceInfo {
	int realDeviceAddress;
	char * controllerName;
	char * portName;
	char deviceStatus;
	char deviceErrorStatus;
} vmApiRealDeviceInfo;

typedef struct _vmApiVswitchInfo {
	char * switchName;
	char transportType;
	char portType;
	int queueMemoryLimit;
	char routingValue;
	int vlanId;
	int nativeVlanId;
	unsigned long long macId;
	char grvpRequestAttribute;
	char grvpEnabledAttribute;
	char switchStatus;
	int realDeviceCount;
	vmApiRealDeviceInfo * realDeviceList;
	int authorizedUserCount;
	vmApiAuthorizedUserInfo * authorizedUserList;
	int connectedAdapterCount;
	vmApiVirtualNetworkConnectedAdapterInfo * connectedAdapterList; // Shares common structure with   Virtual network lan query
} vmApiVswitchInfo;

typedef struct _vmApiVirtualNetworkVswitchQueryOutput {
	commonOutputFields common;
	int vswitchCount;
	vmApiVswitchInfo * vswitchList;
} vmApiVirtualNetworkVswitchQueryOutput;

// Parser table for Virtual_Network_Vswitch_Query
static tableLayout Virtual_Network_Vswitch_Query_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkVswitchQueryOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkVswitchQueryOutput, common.requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkVswitchQueryOutput, common.returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkVswitchQueryOutput, common.reasonCode) },

{ APITYPE_ARRAY_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
		vmApiVirtualNetworkVswitchQueryOutput, vswitchList) }, {
		APITYPE_ARRAY_STRUCT_COUNT, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		offsetof(vmApiVirtualNetworkVswitchQueryOutput, vswitchCount) }, {
		APITYPE_STRUCT_LEN, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
		sizeof(vmApiVswitchInfo) }, { APITYPE_STRING_LEN, 1, 8, STRUCT_INDX_1,
		NEST_LEVEL_1, offsetof(vmApiVswitchInfo, switchName) }, { APITYPE_INT1,
		1, 1, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(vmApiVswitchInfo,
				transportType) }, { APITYPE_INT1, 1, 1, STRUCT_INDX_1,
		NEST_LEVEL_1, offsetof(vmApiVswitchInfo, portType) }, { APITYPE_INT4,
		4, 4, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(vmApiVswitchInfo,
				queueMemoryLimit) }, { APITYPE_INT1, 1, 1, STRUCT_INDX_1,
		NEST_LEVEL_1, offsetof(vmApiVswitchInfo, routingValue) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
				vmApiVswitchInfo, vlanId) },
		{ APITYPE_INT4, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
				vmApiVswitchInfo, nativeVlanId) },
		{ APITYPE_INT8, 8, 8, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
				vmApiVswitchInfo, macId) }, { APITYPE_INT1, 1, 1,
				STRUCT_INDX_1, NEST_LEVEL_1, offsetof(vmApiVswitchInfo,
						grvpRequestAttribute) }, { APITYPE_INT1, 1, 1,
				STRUCT_INDX_1, NEST_LEVEL_1, offsetof(vmApiVswitchInfo,
						grvpEnabledAttribute) }, { APITYPE_INT1, 1, 1,
				STRUCT_INDX_1, NEST_LEVEL_1, offsetof(vmApiVswitchInfo,
						switchStatus) },

		{ APITYPE_ARRAY_LEN, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
				vmApiVswitchInfo, realDeviceList) }, {
				APITYPE_ARRAY_STRUCT_COUNT, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
				offsetof(vmApiVswitchInfo, realDeviceCount) }, {
				APITYPE_STRUCT_LEN, 4, 4, STRUCT_INDX_2, NEST_LEVEL_2,
				sizeof(vmApiRealDeviceInfo) }, { APITYPE_INT4, 4, 4,
				STRUCT_INDX_2, NEST_LEVEL_2, offsetof(vmApiRealDeviceInfo,
						realDeviceAddress) }, { APITYPE_STRING_LEN, 0, 71,
				STRUCT_INDX_2, NEST_LEVEL_2, offsetof(vmApiRealDeviceInfo,
						controllerName) }, { APITYPE_STRING_LEN, 0, 16,
				STRUCT_INDX_2, NEST_LEVEL_2, offsetof(vmApiRealDeviceInfo,
						portName) }, { APITYPE_INT1, 1, 1, STRUCT_INDX_2,
				NEST_LEVEL_2, offsetof(vmApiRealDeviceInfo, deviceStatus) }, {
				APITYPE_INT1, 1, 1, STRUCT_INDX_2, NEST_LEVEL_2, offsetof(
						vmApiRealDeviceInfo, deviceErrorStatus) },

		{ APITYPE_ARRAY_LEN, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
				vmApiVswitchInfo, authorizedUserList) }, {
				APITYPE_ARRAY_STRUCT_COUNT, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
				offsetof(vmApiVswitchInfo, authorizedUserCount) }, {
				APITYPE_STRUCT_LEN, 4, 4, STRUCT_INDX_3, NEST_LEVEL_2,
				sizeof(vmApiAuthorizedUserInfo) }, { APITYPE_STRING_LEN, 1, 8,
				STRUCT_INDX_3, NEST_LEVEL_2, offsetof(vmApiAuthorizedUserInfo,
						grantUserid) },

		{ APITYPE_ARRAY_LEN, 4, 4, STRUCT_INDX_3, NEST_LEVEL_2, offsetof(
				vmApiAuthorizedUserInfo, vlanList) }, {
				APITYPE_ARRAY_STRUCT_COUNT, 4, 4, STRUCT_INDX_3, NEST_LEVEL_2,
				offsetof(vmApiAuthorizedUserInfo, vlanCount) }, {
				APITYPE_STRUCT_LEN, 4, 4, STRUCT_INDX_4, NEST_LEVEL_3,
				sizeof(vmApiVlanInfo) }, { APITYPE_INT4, 4, 4, STRUCT_INDX_4,
				NEST_LEVEL_3, offsetof(vmApiVlanInfo, userVlanId) },

		{ APITYPE_ARRAY_LEN, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1, offsetof(
				vmApiVswitchInfo, connectedAdapterList) }, {
				APITYPE_ARRAY_STRUCT_COUNT, 4, 4, STRUCT_INDX_1, NEST_LEVEL_1,
				offsetof(vmApiVswitchInfo, connectedAdapterCount) }, {
				APITYPE_STRUCT_LEN, 4, 4, STRUCT_INDX_5, NEST_LEVEL_2,
				sizeof(vmApiVirtualNetworkConnectedAdapterInfo) },
		{ APITYPE_STRING_LEN, 1, 8, STRUCT_INDX_5, NEST_LEVEL_2, offsetof(
				vmApiVirtualNetworkConnectedAdapterInfo, adapterOwner) }, {
				APITYPE_STRING_LEN, 1, 4, STRUCT_INDX_5, NEST_LEVEL_2,
				offsetof(vmApiVirtualNetworkConnectedAdapterInfo,
						imageDeviceNumber) },

		{ APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };

int smVirtual_Network_Vswitch_Query(
		struct _VmApiInternalContext* vmapiContextP, char * userid,
		int passwordLength, char * password, char * targetIdentifier,
		char * switchName, vmApiVirtualNetworkVswitchQueryOutput ** outData);

// Virtual_Network_Vswitch_Set
typedef commonOutputFields vmApiVirtualNetworkVswitchSetOutput;

// Parser table for Virtual_Network_Vswitch_Set
static tableLayout Virtual_Network_Vswitch_Set_Layout = { {
		APITYPE_BASE_STRUCT_LEN, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0,
		sizeof(vmApiVirtualNetworkVswitchSetOutput) }, { APITYPE_INT4, 4, 4,
		STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkVswitchSetOutput, requestId) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkVswitchSetOutput, returnCode) }, {
		APITYPE_INT4, 4, 4, STRUCT_INDX_0, NEST_LEVEL_0, offsetof(
				vmApiVirtualNetworkVswitchSetOutput, reasonCode) }, {
		APITYPE_END_OF_TABLE, 0, 0, 0, 0 } };
int smVirtual_Network_Vswitch_Set(struct _VmApiInternalContext* vmapiContextP,
		char * userid, int passwordLength, char * password,
		char * targetIdentifier, char * switchName, char * grantUserid,
		char * userVlanId, char * revokeUserid, char * realDeviceAddress,
		char * portName, char * controllerName, char connectionValue,
		int queueMemoryLimit, char routingValue, char portType,
		char updateSystemConfigIndicator, char * systemConfigName,
		char * systemConfigType, char * parmDiskOwner, char * parmDiskNumber,
		char * parmDiskPassword, char * altSystemConfigName,
		char * altSystemConfigType, char * altParmDiskOwner,
		char * altParmDiskNumber, char * altParmDiskPassword, char gvrpValue,
		char * macId, vmApiVirtualNetworkVswitchSetOutput ** outData);

#ifdef __cplusplus
}
#endif

#endif
