DEBUG = -g
CFLAGS = -fPIC
LIB_DIR = $(RPM_BUILD_ROOT)/opt/zhcp/lib
BIN_DIR = $(RPM_BUILD_ROOT)/opt/zhcp/bin
LD_DIR = $(RPM_BUILD_ROOT)/etc/ld.so.conf.d
RA_SRC_DIR = resource_access/src/
RA_INCLUDE_DIR = resource_access/include/
VMAPILIB = libvmapi.so

#-----------------------------------------------------------------------
# Headers
#-----------------------------------------------------------------------
COMMON_HEADERS = $(RA_INCLUDE_DIR)smPublic.h $(RA_INCLUDE_DIR)smTraceAndError.h $(RA_INCLUDE_DIR)smapiTableParser.h $(RA_INCLUDE_DIR)smSocket.h

#-----------------------------------------------------------------------
# Objects for library
#-----------------------------------------------------------------------
OBJECTS = smSocket.o smMemoryGroup.o smapiUtilities.o \
      smapiTableParser.o \
      vmapiAsynchronousNotificationDisableDm.o \
      vmapiAsynchronousNotificationEnableDm.o \
      vmapiAsynchronousNotificationQueryDm.o \
      vmapiAuthorizationListAdd.o \
      vmapiAuthorizationListQuery.o \
      vmapiAuthorizationListRemove.o \
      vmapiCheckAuthentication.o \
      vmapiDirectoryManagerLocalTagDefineDm.o \
      vmapiDirectoryManagerLocalTagDeleteDm.o \
      vmapiDirectoryManagerLocalTagQueryDm.o \
      vmapiDirectoryManagerLocalTagSetDm.o \
      vmapiDirectoryManagerSearchDm.o \
      vmapiDirectoryManagerTaskCancelDm.o \
      vmapiImageActivate.o \
      vmapiImageActiveConfigurationQuery.o \
      vmapiImageCpuDefine.o \
      vmapiImageCpuDefineDm.o \
      vmapiImageCpuDelete.o \
      vmapiImageCpuDeleteDm.o \
      vmapiImageCpuQuery.o \
      vmapiImageCpuQueryDm.o \
      vmapiImageCpuSetMaximumDm.o \
      vmapiImageCreateDm.o \
      vmapiImageDeactivate.o \
      vmapiImageDeleteDm.o \
      vmapiImageDeviceDedicate.o \
      vmapiImageDeviceDedicateDm.o \
      vmapiImageDeviceReset.o \
      vmapiImageDeviceUndedicate.o \
      vmapiImageDeviceUndedicateDm.o \
      vmapiImageDiskCopy.o \
      vmapiImageDiskCopyDm.o \
      vmapiImageDiskCreate.o \
      vmapiImageDiskCreateDm.o \
      vmapiImageDiskDelete.o \
      vmapiImageDiskDeleteDm.o \
      vmapiImageDiskShare.o \
      vmapiImageDiskShareDm.o \
      vmapiImageDiskUnshare.o \
      vmapiImageDiskUnshareDm.o \
      vmapiImageIplDeleteDm.o \
      vmapiImageIplDeviceQuery.o \
      vmapiImageIplQueryDm.o \
      vmapiImageIplSetDm.o \
      vmapiImageLockDm.o \
      vmapiImageNameQueryDm.o \
      vmapiImagePasswordSetDm.o \
      vmapiImageQueryActivateTime.o \
      vmapiImageQueryDm.o \
      vmapiImageRecycle.o \
      vmapiImageReplaceDm.o \
      vmapiImageScsiCharacteristicsDefineDm.o \
      vmapiImageScsiCharacteristicsQueryDm.o \
      vmapiImageStatusQuery.o \
      vmapiImageUnlockDm.o \
      vmapiImageVolumeAdd.o \
      vmapiImageVolumeDelete.o \
      vmapiImageVolumeSpaceDefineDm.o \
      vmapiImageVolumeSpaceQueryDm.o \
      vmapiImageVolumeSpaceRemoveDm.o \
      vmapiNameListAdd.o \
      vmapiNameListDestroy.o \
      vmapiNameListQuery.o \
      vmapiNameListRemove.o \
      vmapiProfileCreateDm.o \
      vmapiProfileDeleteDm.o \
      vmapiProfileQueryDm.o \
      vmapiProfileReplaceDm.o \
      vmapiPrototypeCreateDm.o \
      vmapiPrototypeDeleteDm.o \
      vmapiPrototypeNameQueryDm.o \
      vmapiPrototypeQueryDm.o \
      vmapiPrototypeReplaceDm.o \
      vmapiQueryApiFunctionalLevel.o \
      vmapiQueryAsynchronousOperationDm.o \
      vmapiQueryDirectoryManagerLevelDm.o \
      vmapiSharedMemoryAccessAddDm.o \
      vmapiSharedMemoryAccessQueryDm.o \
      vmapiSharedMemoryAccessRemoveDm.o \
      vmapiSharedMemoryCreate.o \
      vmapiSharedMemoryDelete.o \
      vmapiSharedMemoryQuery.o \
      vmapiSharedMemoryReplace.o \
      vmapiStaticImageChangesActivateDm.o \
      vmapiStaticImageChangesDeactivateDm.o \
      vmapiStaticImageChangesImmediateDm.o \
      vmapiSystemInfoQuery.o \
      vmapiSystemIoQuery.o \
      vmapiVirtualChannelConnectionCreate.o \
      vmapiVirtualChannelConnectionCreateDm.o \
      vmapiVirtualChannelConnectionDelete.o \
      vmapiVirtualChannelConnectionDeleteDm.o \
      vmapiVirtualNetworkAdapterConnectLan.o \
      vmapiVirtualNetworkAdapterConnectLanDm.o \
      vmapiVirtualNetworkAdapterConnectVswitch.o \
      vmapiVirtualNetworkAdapterConnectVswitchDm.o \
      vmapiVirtualNetworkAdapterCreate.o \
      vmapiVirtualNetworkAdapterCreateDm.o \
      vmapiVirtualNetworkAdapterDelete.o \
      vmapiVirtualNetworkAdapterDeleteDm.o \
      vmapiVirtualNetworkAdapterDisconnect.o \
      vmapiVirtualNetworkAdapterDisconnectDm.o \
      vmapiVirtualNetworkAdapterQuery.o \
      vmapiVirtualNetworkLanAccess.o \
      vmapiVirtualNetworkLanAccessQuery.o \
      vmapiVirtualNetworkLanCreate.o \
      vmapiVirtualNetworkLanDelete.o \
      vmapiVirtualNetworkLanQuery.o \
      vmapiVirtualNetworkQueryOsa.o \
      vmapiVirtualNetworkVswitchCreate.o \
      vmapiVirtualNetworkVswitchDelete.o \
      vmapiVirtualNetworkVswitchQuery.o \
      vmapiVirtualNetworkVswitchSet.o \
      vmapiVmrmConfigurationQuery.o \
      vmapiVmrmConfigurationUpdate.o \
      vmapiVmrmMeasurementQuery.o
.PHONY: all install post clean

#-----------------------------------------------------------------------
# All
#-----------------------------------------------------------------------
all: $(VMAPILIB) \
	wrapperutils.o \
	add3390 \
	add3390active \
	add9336 \
	addvdisk \
	addprocessor \
	addnic \
	connectnic2guestlan \
	connectnic2vswitch \
	createvs \
	deleteipl \
	deletevs \
	dedicatedevice \
	disconnectnic \
	getuserentrynames \
	getuserentry \
	getipl \
	getuserprofile \
	getdiskpool \
	getdiskpoolnames \
	queryvolumes \
	removemdisk \
	removenic \
	removeprocessor \
	replacevs \
	setipl \
	setpassword \
	startvs \
	stopvs \
	undedicatedevice
	
#-----------------------------------------------------------------------
# Resource access .o files
#-----------------------------------------------------------------------
smSocket.o : $(RA_SRC_DIR)smSocket.c $(RA_INCLUDE_DIR)smSocket.h $(COMMON_HEADERS)
	gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)smSocket.c

smMemoryGroup.o : $(RA_SRC_DIR)smMemoryGroup.c $(COMMON_HEADERS)
	gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)smMemoryGroup.c

smapiUtilities.o : $(RA_SRC_DIR)smapiUtilities.c $(COMMON_HEADERS)
	gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)smapiUtilities.c

smapiTableParser.o :                           $(RA_SRC_DIR)smapiTableParser.c $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)smapiTableParser.c

vmapiAsynchronousNotificationDisableDm.o :     $(RA_SRC_DIR)vmapiAsynchronousNotificationDisableDm.c $(RA_INCLUDE_DIR)vmapiAsynchronous.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiAsynchronousNotificationDisableDm.c

vmapiAsynchronousNotificationEnableDm.o :      $(RA_SRC_DIR)vmapiAsynchronousNotificationEnableDm.c $(RA_INCLUDE_DIR)vmapiAsynchronous.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiAsynchronousNotificationEnableDm.c

vmapiAsynchronousNotificationQueryDm.o :       $(RA_SRC_DIR)vmapiAsynchronousNotificationQueryDm.c $(RA_INCLUDE_DIR)vmapiAsynchronous.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiAsynchronousNotificationQueryDm.c

vmapiAuthorizationListAdd.o :                  $(RA_SRC_DIR)vmapiAuthorizationListAdd.c $(RA_INCLUDE_DIR)vmapiAuthorization.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiAuthorizationListAdd.c

vmapiAuthorizationListQuery.o :                $(RA_SRC_DIR)vmapiAuthorizationListQuery.c $(RA_INCLUDE_DIR)vmapiAuthorization.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiAuthorizationListQuery.c

vmapiAuthorizationListRemove.o :               $(RA_SRC_DIR)vmapiAuthorizationListRemove.c $(RA_INCLUDE_DIR)vmapiAuthorization.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiAuthorizationListRemove.c

vmapiCheckAuthentication.o :                 $(RA_SRC_DIR)vmapiCheckAuthentication.c $(RA_INCLUDE_DIR)vmapiCheckAuthentication.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiCheckAuthentication.c

vmapiDirectoryManagerLocalTagDefineDm.o :      $(RA_SRC_DIR)vmapiDirectoryManagerLocalTagDefineDm.c $(RA_INCLUDE_DIR)vmapiDirectoryManager.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiDirectoryManagerLocalTagDefineDm.c

vmapiDirectoryManagerLocalTagDeleteDm.o :      $(RA_SRC_DIR)vmapiDirectoryManagerLocalTagDeleteDm.c $(RA_INCLUDE_DIR)vmapiDirectoryManager.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiDirectoryManagerLocalTagDeleteDm.c

vmapiDirectoryManagerLocalTagQueryDm.o :       $(RA_SRC_DIR)vmapiDirectoryManagerLocalTagQueryDm.c $(RA_INCLUDE_DIR)vmapiDirectoryManager.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiDirectoryManagerLocalTagQueryDm.c

vmapiDirectoryManagerLocalTagSetDm.o :         $(RA_SRC_DIR)vmapiDirectoryManagerLocalTagSetDm.c $(RA_INCLUDE_DIR)vmapiDirectoryManager.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiDirectoryManagerLocalTagSetDm.c

vmapiDirectoryManagerSearchDm.o :              $(RA_SRC_DIR)vmapiDirectoryManagerSearchDm.c $(RA_INCLUDE_DIR)vmapiDirectoryManager.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiDirectoryManagerSearchDm.c

vmapiDirectoryManagerTaskCancelDm.o :          $(RA_SRC_DIR)vmapiDirectoryManagerTaskCancelDm.c $(RA_INCLUDE_DIR)vmapiDirectoryManager.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiDirectoryManagerTaskCancelDm.c

vmapiImageActivate.o :                         $(RA_SRC_DIR)vmapiImageActivate.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageActivate.c

vmapiImageActiveConfigurationQuery.o :         $(RA_SRC_DIR)vmapiImageActiveConfigurationQuery.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageActiveConfigurationQuery.c

vmapiImageCpuDefine.o :                        $(RA_SRC_DIR)vmapiImageCpuDefine.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageCpuDefine.c

vmapiImageCpuDefineDm.o :                      $(RA_SRC_DIR)vmapiImageCpuDefineDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageCpuDefineDm.c

vmapiImageCpuDelete.o :                        $(RA_SRC_DIR)vmapiImageCpuDelete.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageCpuDelete.c

vmapiImageCpuDeleteDm.o :                      $(RA_SRC_DIR)vmapiImageCpuDeleteDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageCpuDeleteDm.c

vmapiImageCpuQuery.o :                         $(RA_SRC_DIR)vmapiImageCpuQuery.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageCpuQuery.c

vmapiImageCpuQueryDm.o :                       $(RA_SRC_DIR)vmapiImageCpuQueryDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageCpuQueryDm.c

vmapiImageCpuSetMaximumDm.o :                  $(RA_SRC_DIR)vmapiImageCpuSetMaximumDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageCpuSetMaximumDm.c

vmapiImageCreateDm.o :                         $(RA_SRC_DIR)vmapiImageCreateDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageCreateDm.c

vmapiImageDeactivate.o :                       $(RA_SRC_DIR)vmapiImageDeactivate.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageDeactivate.c

vmapiImageDeleteDm.o :                         $(RA_SRC_DIR)vmapiImageDeleteDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageDeleteDm.c

vmapiImageDeviceDedicate.o :                   $(RA_SRC_DIR)vmapiImageDeviceDedicate.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageDeviceDedicate.c

vmapiImageDeviceDedicateDm.o :                 $(RA_SRC_DIR)vmapiImageDeviceDedicateDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageDeviceDedicateDm.c

vmapiImageDeviceReset.o :                      $(RA_SRC_DIR)vmapiImageDeviceReset.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageDeviceReset.c

vmapiImageDeviceUndedicate.o :                 $(RA_SRC_DIR)vmapiImageDeviceUndedicate.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageDeviceUndedicate.c

vmapiImageDeviceUndedicateDm.o :               $(RA_SRC_DIR)vmapiImageDeviceUndedicateDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageDeviceUndedicateDm.c

vmapiImageDiskCopy.o :                         $(RA_SRC_DIR)vmapiImageDiskCopy.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageDiskCopy.c

vmapiImageDiskCopyDm.o :                       $(RA_SRC_DIR)vmapiImageDiskCopyDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageDiskCopyDm.c

vmapiImageDiskCreate.o :                       $(RA_SRC_DIR)vmapiImageDiskCreate.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageDiskCreate.c

vmapiImageDiskCreateDm.o :                     $(RA_SRC_DIR)vmapiImageDiskCreateDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageDiskCreateDm.c

vmapiImageDiskDelete.o :                       $(RA_SRC_DIR)vmapiImageDiskDelete.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageDiskDelete.c

vmapiImageDiskDeleteDm.o :                     $(RA_SRC_DIR)vmapiImageDiskDeleteDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageDiskDeleteDm.c

vmapiImageDiskShare.o :                        $(RA_SRC_DIR)vmapiImageDiskShare.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageDiskShare.c

vmapiImageDiskShareDm.o :                      $(RA_SRC_DIR)vmapiImageDiskShareDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageDiskShareDm.c

vmapiImageDiskUnshare.o :                      $(RA_SRC_DIR)vmapiImageDiskUnshare.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageDiskUnshare.c

vmapiImageDiskUnshareDm.o :                    $(RA_SRC_DIR)vmapiImageDiskUnshareDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageDiskUnshareDm.c

vmapiImageIplDeleteDm.o :                      $(RA_SRC_DIR)vmapiImageIplDeleteDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageIplDeleteDm.c

vmapiImageIplDeviceQuery.o  :                  $(RA_SRC_DIR)vmapiImageIplDeviceQuery.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageIplDeviceQuery.c

vmapiImageIplQueryDm.o :                       $(RA_SRC_DIR)vmapiImageIplQueryDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageIplQueryDm.c

vmapiImageIplSetDm.o :                         $(RA_SRC_DIR)vmapiImageIplSetDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageIplSetDm.c

vmapiImageLockDm.o :                           $(RA_SRC_DIR)vmapiImageLockDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageLockDm.c

vmapiImageNameQueryDm.o :                      $(RA_SRC_DIR)vmapiImageNameQueryDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageNameQueryDm.c

vmapiImagePasswordSetDm.o :                    $(RA_SRC_DIR)vmapiImagePasswordSetDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImagePasswordSetDm.c

vmapiImageQueryActivateTime.o :                $(RA_SRC_DIR)vmapiImageQueryActivateTime.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageQueryActivateTime.c

vmapiImageQueryDm.o :                          $(RA_SRC_DIR)vmapiImageQueryDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageQueryDm.c

vmapiImageRecycle.o :                          $(RA_SRC_DIR)vmapiImageRecycle.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageRecycle.c

vmapiImageReplaceDm.o :                        $(RA_SRC_DIR)vmapiImageReplaceDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageReplaceDm.c

vmapiImageScsiCharacteristicsDefineDm.o :      $(RA_SRC_DIR)vmapiImageScsiCharacteristicsDefineDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageScsiCharacteristicsDefineDm.c

vmapiImageScsiCharacteristicsQueryDm.o :       $(RA_SRC_DIR)vmapiImageScsiCharacteristicsQueryDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageScsiCharacteristicsQueryDm.c

vmapiImageStatusQuery.o :                      $(RA_SRC_DIR)vmapiImageStatusQuery.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageStatusQuery.c

vmapiImageUnlockDm.o :                         $(RA_SRC_DIR)vmapiImageUnlockDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageUnlockDm.c

vmapiImageVolumeAdd.o :                        $(RA_SRC_DIR)vmapiImageVolumeAdd.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageVolumeAdd.c

vmapiImageVolumeDelete.o :                     $(RA_SRC_DIR)vmapiImageVolumeDelete.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageVolumeDelete.c

vmapiImageVolumeSpaceDefineDm.o :              $(RA_SRC_DIR)vmapiImageVolumeSpaceDefineDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageVolumeSpaceDefineDm.c

vmapiImageVolumeSpaceQueryDm.o :               $(RA_SRC_DIR)vmapiImageVolumeSpaceQueryDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageVolumeSpaceQueryDm.c

vmapiImageVolumeSpaceRemoveDm.o :              $(RA_SRC_DIR)vmapiImageVolumeSpaceRemoveDm.c $(RA_INCLUDE_DIR)vmapiImage.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiImageVolumeSpaceRemoveDm.c

vmapiNameListAdd.o :                           $(RA_SRC_DIR)vmapiNameListAdd.c $(RA_INCLUDE_DIR)vmapiName.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiNameListAdd.c

vmapiNameListDestroy.o :                       $(RA_SRC_DIR)vmapiNameListDestroy.c $(RA_INCLUDE_DIR)vmapiName.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiNameListDestroy.c

vmapiNameListQuery.o :                         $(RA_SRC_DIR)vmapiNameListQuery.c $(RA_INCLUDE_DIR)vmapiName.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiNameListQuery.c

vmapiNameListRemove.o :                        $(RA_SRC_DIR)vmapiNameListRemove.c $(RA_INCLUDE_DIR)vmapiName.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiNameListRemove.c

vmapiProfileCreateDm.o :                       $(RA_SRC_DIR)vmapiProfileCreateDm.c $(RA_INCLUDE_DIR)vmapiProfile.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiProfileCreateDm.c

vmapiProfileDeleteDm.o :                       $(RA_SRC_DIR)vmapiProfileDeleteDm.c $(RA_INCLUDE_DIR)vmapiProfile.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiProfileDeleteDm.c

vmapiProfileQueryDm.o :                        $(RA_SRC_DIR)vmapiProfileQueryDm.c $(RA_INCLUDE_DIR)vmapiProfile.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiProfileQueryDm.c

vmapiProfileReplaceDm.o :                      $(RA_SRC_DIR)vmapiProfileReplaceDm.c $(RA_INCLUDE_DIR)vmapiProfile.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiProfileReplaceDm.c

vmapiPrototypeCreateDm.o :                     $(RA_SRC_DIR)vmapiPrototypeCreateDm.c $(RA_INCLUDE_DIR)vmapiPrototype.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiPrototypeCreateDm.c

vmapiPrototypeDeleteDm.o :                     $(RA_SRC_DIR)vmapiPrototypeDeleteDm.c $(RA_INCLUDE_DIR)vmapiPrototype.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiPrototypeDeleteDm.c

vmapiPrototypeNameQueryDm.o :                  $(RA_SRC_DIR)vmapiPrototypeNameQueryDm.c $(RA_INCLUDE_DIR)vmapiPrototype.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiPrototypeNameQueryDm.c

vmapiPrototypeQueryDm.o :                      $(RA_SRC_DIR)vmapiPrototypeQueryDm.c $(RA_INCLUDE_DIR)vmapiPrototype.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiPrototypeQueryDm.c

vmapiPrototypeReplaceDm.o :                    $(RA_SRC_DIR)vmapiPrototypeReplaceDm.c $(RA_INCLUDE_DIR)vmapiPrototype.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiPrototypeReplaceDm.c

vmapiQueryApiFunctionalLevel.o :               $(RA_SRC_DIR)vmapiQueryApiFunctionalLevel.c $(RA_INCLUDE_DIR)vmapiQuery.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiQueryApiFunctionalLevel.c

vmapiQueryAsynchronousOperationDm.o :          $(RA_SRC_DIR)vmapiQueryAsynchronousOperationDm.c $(RA_INCLUDE_DIR)vmapiQuery.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiQueryAsynchronousOperationDm.c

vmapiQueryDirectoryManagerLevelDm.o :          $(RA_SRC_DIR)vmapiQueryDirectoryManagerLevelDm.c $(RA_INCLUDE_DIR)vmapiQuery.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiQueryDirectoryManagerLevelDm.c

vmapiSharedMemoryAccessAddDm.o :               $(RA_SRC_DIR)vmapiSharedMemoryAccessAddDm.c $(RA_INCLUDE_DIR)vmapiShared.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiSharedMemoryAccessAddDm.c

vmapiSharedMemoryAccessQueryDm.o :             $(RA_SRC_DIR)vmapiSharedMemoryAccessQueryDm.c $(RA_INCLUDE_DIR)vmapiShared.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiSharedMemoryAccessQueryDm.c

vmapiSharedMemoryAccessRemoveDm.o :            $(RA_SRC_DIR)vmapiSharedMemoryAccessRemoveDm.c $(RA_INCLUDE_DIR)vmapiShared.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiSharedMemoryAccessRemoveDm.c

vmapiSharedMemoryCreate.o :                    $(RA_SRC_DIR)vmapiSharedMemoryCreate.c $(RA_INCLUDE_DIR)vmapiShared.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiSharedMemoryCreate.c

vmapiSharedMemoryDelete.o :                    $(RA_SRC_DIR)vmapiSharedMemoryDelete.c $(RA_INCLUDE_DIR)vmapiShared.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiSharedMemoryDelete.c

vmapiSharedMemoryQuery.o :                     $(RA_SRC_DIR)vmapiSharedMemoryQuery.c $(RA_INCLUDE_DIR)vmapiShared.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiSharedMemoryQuery.c

vmapiSharedMemoryReplace.o :                   $(RA_SRC_DIR)vmapiSharedMemoryReplace.c $(RA_INCLUDE_DIR)vmapiShared.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiSharedMemoryReplace.c

vmapiStaticImageChangesActivateDm.o :          $(RA_SRC_DIR)vmapiStaticImageChangesActivateDm.c $(RA_INCLUDE_DIR)vmapiStatic.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiStaticImageChangesActivateDm.c

vmapiStaticImageChangesDeactivateDm.o :        $(RA_SRC_DIR)vmapiStaticImageChangesDeactivateDm.c $(RA_INCLUDE_DIR)vmapiStatic.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiStaticImageChangesDeactivateDm.c

vmapiStaticImageChangesImmediateDm.o :         $(RA_SRC_DIR)vmapiStaticImageChangesImmediateDm.c $(RA_INCLUDE_DIR)vmapiStatic.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiStaticImageChangesImmediateDm.c

vmapiSystemInfoQuery.o :                       $(RA_SRC_DIR)vmapiSystemInfoQuery.c $(RA_INCLUDE_DIR)vmapiSystem.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiSystemInfoQuery.c

vmapiSystemIoQuery.o :                         $(RA_SRC_DIR)vmapiSystemIoQuery.c $(RA_INCLUDE_DIR)vmapiSystem.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiSystemIoQuery.c

vmapiVirtualChannelConnectionCreate.o :        $(RA_SRC_DIR)vmapiVirtualChannelConnectionCreate.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualChannelConnectionCreate.c

vmapiVirtualChannelConnectionCreateDm.o :      $(RA_SRC_DIR)vmapiVirtualChannelConnectionCreateDm.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualChannelConnectionCreateDm.c

vmapiVirtualChannelConnectionDelete.o :        $(RA_SRC_DIR)vmapiVirtualChannelConnectionDelete.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualChannelConnectionDelete.c

vmapiVirtualChannelConnectionDeleteDm.o :      $(RA_SRC_DIR)vmapiVirtualChannelConnectionDeleteDm.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualChannelConnectionDeleteDm.c

vmapiVirtualNetworkAdapterConnectLan.o :       $(RA_SRC_DIR)vmapiVirtualNetworkAdapterConnectLan.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkAdapterConnectLan.c

vmapiVirtualNetworkAdapterConnectLanDm.o :     $(RA_SRC_DIR)vmapiVirtualNetworkAdapterConnectLanDm.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkAdapterConnectLanDm.c

vmapiVirtualNetworkAdapterConnectVswitch.o :   $(RA_SRC_DIR)vmapiVirtualNetworkAdapterConnectVswitch.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkAdapterConnectVswitch.c

vmapiVirtualNetworkAdapterConnectVswitchDm.o : $(RA_SRC_DIR)vmapiVirtualNetworkAdapterConnectVswitchDm.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkAdapterConnectVswitchDm.c

vmapiVirtualNetworkAdapterCreate.o :           $(RA_SRC_DIR)vmapiVirtualNetworkAdapterCreate.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkAdapterCreate.c

vmapiVirtualNetworkAdapterCreateDm.o :         $(RA_SRC_DIR)vmapiVirtualNetworkAdapterCreateDm.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkAdapterCreateDm.c

vmapiVirtualNetworkAdapterDelete.o :           $(RA_SRC_DIR)vmapiVirtualNetworkAdapterDelete.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkAdapterDelete.c

vmapiVirtualNetworkAdapterDeleteDm.o :         $(RA_SRC_DIR)vmapiVirtualNetworkAdapterDeleteDm.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkAdapterDeleteDm.c

vmapiVirtualNetworkAdapterDisconnect.o :       $(RA_SRC_DIR)vmapiVirtualNetworkAdapterDisconnect.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkAdapterDisconnect.c

vmapiVirtualNetworkAdapterDisconnectDm.o :     $(RA_SRC_DIR)vmapiVirtualNetworkAdapterDisconnectDm.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkAdapterDisconnectDm.c

vmapiVirtualNetworkAdapterQuery.o :            $(RA_SRC_DIR)vmapiVirtualNetworkAdapterQuery.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkAdapterQuery.c

vmapiVirtualNetworkLanAccess.o :               $(RA_SRC_DIR)vmapiVirtualNetworkLanAccess.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkLanAccess.c

vmapiVirtualNetworkLanAccessQuery.o :          $(RA_SRC_DIR)vmapiVirtualNetworkLanAccessQuery.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkLanAccessQuery.c

vmapiVirtualNetworkLanCreate.o :               $(RA_SRC_DIR)vmapiVirtualNetworkLanCreate.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkLanCreate.c

vmapiVirtualNetworkLanDelete.o :               $(RA_SRC_DIR)vmapiVirtualNetworkLanDelete.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkLanDelete.c

vmapiVirtualNetworkLanQuery.o :                $(RA_SRC_DIR)vmapiVirtualNetworkLanQuery.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkLanQuery.c

vmapiVirtualNetworkQueryOsa.o :                $(RA_SRC_DIR)vmapiVirtualNetworkQueryOsa.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkQueryOsa.c

vmapiVirtualNetworkVswitchCreate.o :           $(RA_SRC_DIR)vmapiVirtualNetworkVswitchCreate.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkVswitchCreate.c

vmapiVirtualNetworkVswitchDelete.o :           $(RA_SRC_DIR)vmapiVirtualNetworkVswitchDelete.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkVswitchDelete.c

vmapiVirtualNetworkVswitchQuery.o :            $(RA_SRC_DIR)vmapiVirtualNetworkVswitchQuery.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkVswitchQuery.c

vmapiVirtualNetworkVswitchSet.o :              $(RA_SRC_DIR)vmapiVirtualNetworkVswitchSet.c $(RA_INCLUDE_DIR)vmapiVirtual.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVirtualNetworkVswitchSet.c

vmapiVmrmConfigurationQuery.o :                $(RA_SRC_DIR)vmapiVmrmConfigurationQuery.c $(RA_INCLUDE_DIR)vmapiVMRM.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVmrmConfigurationQuery.c

vmapiVmrmConfigurationUpdate.o :               $(RA_SRC_DIR)vmapiVmrmConfigurationUpdate.c $(RA_INCLUDE_DIR)vmapiVMRM.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVmrmConfigurationUpdate.c

vmapiVmrmMeasurementQuery.o :                  $(RA_SRC_DIR)vmapiVmrmMeasurementQuery.c $(RA_INCLUDE_DIR)vmapiVMRM.h $(COMMON_HEADERS)
		gcc -c $(CFLAGS) $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)vmapiVmrmMeasurementQuery.c

#-----------------------------------------------------------------------
# Resource access libraries
#-----------------------------------------------------------------------
$(VMAPILIB) : $(OBJECTS)
	gcc -Wl,-d -shared -pthread -ldl -o $(VMAPILIB) $(OBJECTS)

#-----------------------------------------------------------------------
# Resource access executables
#-----------------------------------------------------------------------
wrapperutils.o : $(RA_SRC_DIR)wrapperutils.c $(RA_INCLUDE_DIR)smPublic.h $(RA_INCLUDE_DIR)vmapiImage.h
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)wrapperutils.c

add3390 : add3390.o $(VMAPILIB)
	gcc -o add3390  -L./ -lvmapi wrapperutils.o add3390.o

add3390.o : $(RA_SRC_DIR)add3390.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)add3390.c

add3390active : add3390active.o $(VMAPILIB)
	gcc -o add3390active  -L./ -lvmapi wrapperutils.o add3390active.o

add3390active.o : $(RA_SRC_DIR)add3390active.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)add3390active.c

add9336 : add9336.o $(VMAPILIB)
	gcc -o add9336  -L./ -lvmapi wrapperutils.o add9336.o

add9336.o : $(RA_SRC_DIR)add9336.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)add9336.c

addvdisk : addvdisk.o $(VMAPILIB)
	gcc -o addvdisk  -L./ -lvmapi wrapperutils.o addvdisk.o

addvdisk.o : $(RA_SRC_DIR)addvdisk.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)addvdisk.c

addprocessor : addprocessor.o $(VMAPILIB)
	gcc -o addprocessor  -L./ -lvmapi wrapperutils.o addprocessor.o

addprocessor.o : $(RA_SRC_DIR)addprocessor.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)addprocessor.c

addnic : addnic.o $(VMAPILIB)
	gcc -o addnic  -L./ -lvmapi wrapperutils.o addnic.o

addnic.o : $(RA_SRC_DIR)addnic.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)addnic.c

connectnic2guestlan : connectnic2guestlan.o $(VMAPILIB)
	gcc -o connectnic2guestlan  -L./ -lvmapi wrapperutils.o connectnic2guestlan.o

connectnic2guestlan.o : $(RA_SRC_DIR)connectnic2guestlan.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)connectnic2guestlan.c

connectnic2vswitch : connectnic2vswitch.o $(VMAPILIB)
	gcc -o connectnic2vswitch  -L./ -lvmapi wrapperutils.o connectnic2vswitch.o

connectnic2vswitch.o : $(RA_SRC_DIR)connectnic2vswitch.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)connectnic2vswitch.c

createvs : createvs.o $(VMAPILIB)
	gcc -o createvs  -L./ -lvmapi wrapperutils.o createvs.o

createvs.o : $(RA_SRC_DIR)createvs.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)createvs.c

deletevs : deletevs.o $(VMAPILIB)
	gcc -o deletevs  -L./ -lvmapi wrapperutils.o deletevs.o

deletevs.o : $(RA_SRC_DIR)deletevs.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)deletevs.c

dedicatedevice : dedicatedevice.o $(VMAPILIB)
	gcc -o dedicatedevice -L./ -lvmapi wrapperutils.o dedicatedevice.o

dedicatedevice.o : $(RA_SRC_DIR)dedicatedevice.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)dedicatedevice.c

deleteipl : deleteipl.o $(VMAPILIB)
	gcc -o deleteipl  -L./ -lvmapi wrapperutils.o deleteipl.o

deleteipl.o : $(RA_SRC_DIR)deleteipl.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)deleteipl.c

disconnectnic : disconnectnic.o $(VMAPILIB)
	gcc -o disconnectnic  -L./ -lvmapi wrapperutils.o disconnectnic.o

disconnectnic.o : $(RA_SRC_DIR)disconnectnic.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)disconnectnic.c

getuserentrynames : getuserentrynames.o $(VMAPILIB)
	gcc -o getuserentrynames  -L./ -lvmapi wrapperutils.o getuserentrynames.o

getuserentrynames.o : $(RA_SRC_DIR)getuserentrynames.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)getuserentrynames.c

getuserentry : getuserentry.o $(VMAPILIB)
	gcc -o getuserentry -L./ -lvmapi wrapperutils.o getuserentry.o

getuserentry.o : $(RA_SRC_DIR)getuserentry.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)getuserentry.c

getipl : getipl.o $(VMAPILIB)
	gcc -o getipl  -L./ -lvmapi wrapperutils.o getipl.o

getipl.o : $(RA_SRC_DIR)getipl.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)getipl.c

getuserprofile : getuserprofile.o $(VMAPILIB)
	gcc -o getuserprofile -L./ -lvmapi wrapperutils.o getuserprofile.o

getuserprofile.o : $(RA_SRC_DIR)getuserprofile.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)getuserprofile.c

getdiskpool : getdiskpool.o $(VMAPILIB)
	gcc -o getdiskpool  -L./ -lvmapi wrapperutils.o getdiskpool.o

getdiskpool.o : $(RA_SRC_DIR)getdiskpool.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)getdiskpool.c

getdiskpoolnames : getdiskpoolnames.o $(VMAPILIB)
	gcc -o getdiskpoolnames  -L./ -lvmapi wrapperutils.o getdiskpoolnames.o

getdiskpoolnames.o : $(RA_SRC_DIR)getdiskpoolnames.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)getdiskpoolnames.c

queryvolumes : queryvolumes.o $(VMAPILIB)
	gcc -o queryvolumes -L./ -lvmapi wrapperutils.o queryvolumes.o

queryvolumes.o : $(RA_SRC_DIR)queryvolumes.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)queryvolumes.c

removemdisk : removemdisk.o $(VMAPILIB)
	gcc -o removemdisk  -L./ -lvmapi wrapperutils.o removemdisk.o

removemdisk.o : $(RA_SRC_DIR)removemdisk.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)removemdisk.c

removenic : removenic.o $(VMAPILIB)
	gcc -o removenic  -L./ -lvmapi wrapperutils.o removenic.o

removenic.o : $(RA_SRC_DIR)removenic.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)removenic.c

removeprocessor : removeprocessor.o $(VMAPILIB)
	gcc -o removeprocessor  -L./ -lvmapi wrapperutils.o removeprocessor.o

removeprocessor.o : $(RA_SRC_DIR)removeprocessor.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)removeprocessor.c

replacevs : replacevs.o $(VMAPILIB)
	gcc -o replacevs  -L./ -lvmapi wrapperutils.o replacevs.o

replacevs.o : $(RA_SRC_DIR)replacevs.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)replacevs.c
	
setipl : setipl.o $(VMAPILIB)
	gcc -o setipl  -L./ -lvmapi wrapperutils.o setipl.o

setipl.o : $(RA_SRC_DIR)setipl.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)setipl.c
	
setpassword : setpassword.o $(VMAPILIB)
	gcc -o setpassword  -L./ -lvmapi wrapperutils.o setpassword.o

setpassword.o : $(RA_SRC_DIR)setpassword.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)setpassword.c

startvs : startvs.o $(VMAPILIB)
	gcc -o startvs  -L./ -lvmapi wrapperutils.o startvs.o

startvs.o : $(RA_SRC_DIR)startvs.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)startvs.c

stopvs : stopvs.o $(VMAPILIB)
	gcc -o stopvs  -L./ -lvmapi wrapperutils.o stopvs.o

stopvs.o : $(RA_SRC_DIR)stopvs.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)stopvs.c

undedicatedevice : undedicatedevice.o $(VMAPILIB)
	gcc -o undedicatedevice  -L./ -lvmapi wrapperutils.o undedicatedevice.o

undedicatedevice.o : $(RA_SRC_DIR)undedicatedevice.c
	gcc -c $(DEBUG) -I$(RA_INCLUDE_DIR) $(RA_SRC_DIR)undedicatedevice.c
	
#-----------------------------------------------------------------------
# Install
#-----------------------------------------------------------------------
install:
	mkdir -p $(LIB_DIR)
	install $(VMAPILIB) $(LIB_DIR)
	mkdir -p $(BIN_DIR)
	install stopvs $(BIN_DIR)
	install add3390 $(BIN_DIR)
	install add3390active $(BIN_DIR)
	install add9336 $(BIN_DIR)
	install addvdisk $(BIN_DIR)
	install addprocessor $(BIN_DIR)
	install addnic $(BIN_DIR)
	install connectnic2guestlan $(BIN_DIR)
	install connectnic2vswitch $(BIN_DIR)
	install createvs $(BIN_DIR)
	install deletevs $(BIN_DIR)
	install dedicatedevice $(BIN_DIR)
	install deleteipl $(BIN_DIR)
	install disconnectnic $(BIN_DIR)
	install getuserentrynames $(BIN_DIR)
	install getuserentry $(BIN_DIR)
	install getipl $(BIN_DIR)
	install getuserprofile $(BIN_DIR)
	install getdiskpool $(BIN_DIR)
	install getdiskpoolnames $(BIN_DIR)
	install queryvolumes $(BIN_DIR)
	install removemdisk $(BIN_DIR)
	install removenic $(BIN_DIR)
	install removeprocessor $(BIN_DIR)
	install replacevs $(BIN_DIR)
	install setipl $(BIN_DIR)
	install setpassword $(BIN_DIR)
	install startvs $(BIN_DIR)
	install stopvs $(BIN_DIR)
	install undedicatedevice $(BIN_DIR)
	mkdir -p $(LD_DIR)
	install -m 644 config/zhcp.conf $(LD_DIR)

#-----------------------------------------------------------------------
# Post
#-----------------------------------------------------------------------
post:
	ldconfig

#-----------------------------------------------------------------------
# Clean
#-----------------------------------------------------------------------
clean:
	rm -f *.o *.so $(VMAPILIB) 
	rm add3390
	rm add3390active
	rm add9336
	rm addvdisk
	rm addprocessor
	rm addnic
	rm connectnic2guestlan
	rm connectnic2vswitch
	rm createvs
	rm deleteipl
	rm deletevs
	rm dedicatedevice
	rm disconnectnic
	rm getuserentrynames
	rm getuserentry
	rm getipl
	rm getuserprofile
	rm getdiskpool
	rm getdiskpoolnames
	rm queryvolumes
	rm removemdisk
	rm removenic
	rm removeprocessor
	rm replacevs
	rm setipl
	rm setpassword
	rm startvs
	rm stopvs
	rm undedicatedevice
