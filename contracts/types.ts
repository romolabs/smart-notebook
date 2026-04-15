export type NoteType = 'general' | 'meeting' | 'class' | 'research' | 'journal';

export interface Note {
  id: string;
  title: string;
  noteType: NoteType;
  tags: string[];
  createdAt: string;
  updatedAt: string;
  archivedAt?: string | null;
}

export type EnhancementMode = 'local_fast' | 'cloud_accurate';

export interface NoteVersion {
  id: string;
  noteId: string;
  versionNumber: number;
  rawContent: string;
  enhancedContent: string;
  enhancementMode: EnhancementMode;
  pipelineRunId: string;
  createdAt: string;
}

export type ChangeKind =
  | 'spelling'
  | 'formatting'
  | 'clarity'
  | 'summary'
  | 'action_item'
  | 'verification_warning';

export interface TextSpan {
  start: number;
  end: number;
}

export interface ChangeItem {
  id: string;
  versionId: string;
  kind: ChangeKind;
  rawText: string;
  enhancedText: string;
  confidence: number;
  explanation?: string;
  sourceSpan?: TextSpan | null;
  targetSpan?: TextSpan | null;
}

export type VerificationStatus = 'unverified' | 'likely_wrong' | 'needs_source' | 'resolved';

export interface VerificationFlag {
  id: string;
  versionId: string;
  claimText: string;
  status: VerificationStatus;
  confidence: number;
  reason?: string;
  suggestedCorrection?: string;
  span?: TextSpan | null;
}

export type PipelineProcessor = 'spellcheck' | 'format' | 'clarify' | 'verify';

export interface EnhancementPipelineRequest {
  noteId: string;
  versionId?: string | null;
  rawContent: string;
  noteType: NoteType;
  enhancementMode: EnhancementMode;
  enabledProcessors: PipelineProcessor[];
  locale?: string;
}

export interface EnhancementPipelineResult {
  noteId: string;
  versionId: string;
  status: 'ok' | 'partial' | 'failed';
  enhancedContent: string;
  changeItems: ChangeItem[];
  verificationFlags: VerificationFlag[];
  modelTrace?: string;
}

