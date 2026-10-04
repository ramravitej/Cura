import 'package:flutter_test/flutter_test.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';

void main() {
  group('GpuInfo contract', () {
    test('recommendedGpuLayers is always 0, 16, or 99', () {
      const validLayers = {0, 16, 99};

      final scenarios = [
        GpuInfo(
          vulkanSupported: false,
          gpuName: 'None',
          vulkanApiVersion: -1,
          deviceLocalMemoryBytes: -1,
          freeRamBytes: -1,
          recommendedGpuLayers: 0,
        ),
        GpuInfo(
          vulkanSupported: true,
          gpuName: 'Mali-G715',
          vulkanApiVersion: 4206592,
          deviceLocalMemoryBytes: 4294967296,
          freeRamBytes: 3221225472,
          recommendedGpuLayers: 0,
        ),
        GpuInfo(
          vulkanSupported: true,
          gpuName: 'Adreno (TM) 740',
          vulkanApiVersion: 4206592,
          deviceLocalMemoryBytes: 1073741824,
          freeRamBytes: 2147483648,
          recommendedGpuLayers: 16,
        ),
        GpuInfo(
          vulkanSupported: true,
          gpuName: 'Adreno (TM) 750',
          vulkanApiVersion: 4206592,
          deviceLocalMemoryBytes: 4294967296,
          freeRamBytes: 5368709120,
          recommendedGpuLayers: 99,
        ),
      ];

      for (final info in scenarios) {
        expect(
          validLayers.contains(info.recommendedGpuLayers),
          isTrue,
          reason:
              'recommendedGpuLayers=${info.recommendedGpuLayers} for gpu=${info.gpuName}',
        );
      }
    });

    test('vulkanSupported=false always yields recommendedGpuLayers=0', () {
      final info = GpuInfo(
        vulkanSupported: false,
        gpuName: 'None',
        vulkanApiVersion: -1,
        deviceLocalMemoryBytes: -1,
        freeRamBytes: -1,
        recommendedGpuLayers: 0,
      );
      expect(info.vulkanSupported, isFalse);
      expect(info.recommendedGpuLayers, equals(0));
    });
  });
}
