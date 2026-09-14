import { jsonStore, WorkSession } from "../store/jsonStore.js";

export type { WorkSession };

export const sessionService = {
  async getActive(): Promise<WorkSession | null> {
    return jsonStore.getActiveSession();
  },

  async start(params: {
    taskId: string;
    taskName: string;
    taskUrl: string;
    timedoctorOk: boolean;
  }): Promise<WorkSession> {
    return jsonStore.startSession(params);
  },

  async stopActive(): Promise<WorkSession | null> {
    return jsonStore.stopActiveSession();
  },

  async totalSecondsForTask(taskId: string): Promise<number> {
    return jsonStore.totalSecondsForTask(taskId);
  },
};

export const eventLog = {
  async record(eventType: string, detail: Record<string, unknown>): Promise<void> {
    jsonStore.recordEvent(eventType, detail);
  },
};
