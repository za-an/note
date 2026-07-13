import { ClassCourse, UserInfo } from '../model/Models';

/**
 * 全局会话状态：当前登录用户 / 当前课程集合 / 页面间传参。
 * Demo 采用静态字段（页面在 aboutToAppear 读取），后续可迁移 AppStorage。
 */
export class GlobalState {
  static user: UserInfo | null = null;
  static course: ClassCourse | null = null;
  /** 录音结束后跳课时详情用 */
  static currentSessionId: number = -1;

  static isTeacher(): boolean {
    return GlobalState.user !== null && GlobalState.user.role === 'teacher';
  }

  static userId(): number {
    return GlobalState.user === null ? -1 : GlobalState.user.id;
  }

  static courseId(): number {
    return GlobalState.course === null ? -1 : GlobalState.course.id;
  }
}
