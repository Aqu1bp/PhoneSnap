import * as ScreenCapture from 'expo-screen-capture';
import { captureRef } from 'react-native-view-shot';

type RootRef = Parameters<typeof captureRef>[0];
type ScreenshotSubscription = ReturnType<typeof ScreenCapture.addScreenshotListener>;

export type PhoneSnapOptions = {
  uploadUrl: string;
  token: string;
  rootRef: RootRef;
};

let subscription: ScreenshotSubscription | undefined;
let currentOptions: PhoneSnapOptions | undefined;
let uploadInFlight = false;

export function startPhoneSnap(options: PhoneSnapOptions): void {
  if (!__DEV__) {
    return;
  }

  currentOptions = options;

  if (subscription) {
    return;
  }

  subscription = ScreenCapture.addScreenshotListener(() => {
    void sendSnapshot();
  });
}

export function stopPhoneSnap(): void {
  subscription?.remove();
  subscription = undefined;
  currentOptions = undefined;
}

async function sendSnapshot(): Promise<void> {
  if (!__DEV__ || uploadInFlight || !currentOptions) {
    return;
  }

  uploadInFlight = true;
  const { uploadUrl, token, rootRef } = currentOptions;

  try {
    const uri = await captureRef(rootRef, {
      format: 'png',
      quality: 1,
      result: 'tmpfile'
    });
    const form = new FormData();
    form.append('image', {
      uri,
      type: 'image/png',
      name: 'phonesnap.png'
    } as unknown as Blob);

    await fetch(uploadUrl, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`
      },
      body: form
    });
  } finally {
    uploadInFlight = false;
  }
}
