import { useEffect, useRef, useState } from 'react';

export function CameraCapture({
  busy,
  onCapture,
  onClose,
}: {
  busy: boolean;
  onCapture: (image: Blob) => Promise<void>;
  onClose: () => void;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | undefined>(undefined);
  const [error, setError] = useState('');

  useEffect(() => {
    let disposed = false;
    void navigator.mediaDevices
      .getUserMedia({
        audio: false,
        video: { facingMode: { ideal: 'environment' } },
      })
      .then((stream) => {
        if (disposed) {
          stream.getTracks().forEach((track) => track.stop());
          return;
        }
        streamRef.current = stream;
        if (videoRef.current) videoRef.current.srcObject = stream;
      })
      .catch(() =>
        setError(
          'Camera access is unavailable. Close this view and use manual search.',
        ),
      );
    return () => {
      disposed = true;
      streamRef.current?.getTracks().forEach((track) => track.stop());
    };
  }, []);

  async function capture() {
    const video = videoRef.current;
    if (!video || video.videoWidth === 0 || video.videoHeight === 0) {
      setError('The camera is not ready yet.');
      return;
    }
    const scale = Math.min(1, 1280 / video.videoWidth);
    const canvas = document.createElement('canvas');
    canvas.width = Math.round(video.videoWidth * scale);
    canvas.height = Math.round(video.videoHeight * scale);
    canvas
      .getContext('2d', { alpha: false })
      ?.drawImage(video, 0, 0, canvas.width, canvas.height);
    const image = await new Promise<Blob | null>((resolve) =>
      canvas.toBlob(resolve, 'image/jpeg', 0.85),
    );
    if (!image) {
      setError('The image could not be captured. Use manual search.');
      return;
    }
    await onCapture(image);
  }

  return (
    <div
      aria-label="Product camera"
      aria-modal="true"
      className="camera-modal"
      role="dialog"
    >
      <div className="camera-panel">
        <div className="camera-heading">
          <div>
            <p className="eyebrow">AI recognition</p>
            <h2>Point at the product</h2>
          </div>
          <button
            className="camera-close"
            disabled={busy}
            onClick={onClose}
            type="button"
          >
            Close
          </button>
        </div>
        <div className="camera-viewport">
          <video autoPlay muted playsInline ref={videoRef} />
          <span aria-hidden="true" className="camera-guide" />
        </div>
        {error && <p className="error-message">{error}</p>}
        <button
          className="primary-button camera-shutter"
          disabled={busy || Boolean(error)}
          onClick={() => void capture()}
          type="button"
        >
          {busy ? 'Recognising…' : 'Capture & recognise'}
        </button>
      </div>
    </div>
  );
}
