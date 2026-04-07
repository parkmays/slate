// Generated from Supabase project `ynachumtgwkrpeuxjevf`
// Source: Supabase MCP `generate_typescript_types`
// Regenerate with: Supabase MCP generate_typescript_types(project_id)

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  __InternalSupabase: {
    PostgrestVersion: "14.4"
  }
  public: {
    Tables: {
      annotation_replies: {
        Row: {
          annotation_id: string
          author_id: string
          author_name: string
          content: string
          created_at: string
          id: string
        }
        Insert: {
          annotation_id: string
          author_id: string
          author_name: string
          content: string
          created_at?: string
          id?: string
        }
        Update: {
          annotation_id?: string
          author_id?: string
          author_name?: string
          content?: string
          created_at?: string
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "annotation_replies_annotation_id_fkey"
            columns: ["annotation_id"]
            isOneToOne: false
            referencedRelation: "annotations"
            referencedColumns: ["id"]
          },
        ]
      }
      annotations: {
        Row: {
          author_id: string
          author_name: string
          clip_id: string
          content: string
          created_at: string
          id: string
          is_private: boolean
          is_resolved: boolean
          resolved_at: string | null
          timecode: string
          timecode_seconds: number | null
          timestamp: string
          type: string
          updated_at: string
          voice_url: string | null
        }
        Insert: {
          author_id: string
          author_name: string
          clip_id: string
          content: string
          created_at?: string
          id?: string
          is_private?: boolean
          is_resolved?: boolean
          resolved_at?: string | null
          timecode: string
          timecode_seconds?: number | null
          timestamp?: string
          type: string
          updated_at?: string
          voice_url?: string | null
        }
        Update: {
          author_id?: string
          author_name?: string
          clip_id?: string
          content?: string
          created_at?: string
          id?: string
          is_private?: boolean
          is_resolved?: boolean
          resolved_at?: string | null
          timecode?: string
          timecode_seconds?: number | null
          timestamp?: string
          type?: string
          updated_at?: string
          voice_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "annotations_clip_id_fkey"
            columns: ["clip_id"]
            isOneToOne: false
            referencedRelation: "clips"
            referencedColumns: ["id"]
          },
        ]
      }
      assemblies: {
        Row: {
          created_at: string
          id: string
          metadata: Json
          name: string
          project_id: string
          updated_at: string
          version: string
        }
        Insert: {
          created_at?: string
          id?: string
          metadata?: Json
          name: string
          project_id: string
          updated_at?: string
          version: string
        }
        Update: {
          created_at?: string
          id?: string
          metadata?: Json
          name?: string
          project_id?: string
          updated_at?: string
          version?: string
        }
        Relationships: [
          {
            foreignKeyName: "assemblies_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      assembly_clips: {
        Row: {
          assembly_id: string
          clip_id: string
          created_at: string
          duration: string
          id: string
          in_point: string
          notes: string | null
          order: number
          out_point: string
        }
        Insert: {
          assembly_id: string
          clip_id: string
          created_at?: string
          duration: string
          id?: string
          in_point: string
          notes?: string | null
          order: number
          out_point: string
        }
        Update: {
          assembly_id?: string
          clip_id?: string
          created_at?: string
          duration?: string
          id?: string
          in_point?: string
          notes?: string | null
          order?: number
          out_point?: string
        }
        Relationships: [
          {
            foreignKeyName: "assembly_clips_assembly_id_fkey"
            columns: ["assembly_id"]
            isOneToOne: false
            referencedRelation: "assemblies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assembly_clips_clip_id_fkey"
            columns: ["clip_id"]
            isOneToOne: false
            referencedRelation: "clips"
            referencedColumns: ["id"]
          },
        ]
      }
      assembly_versions: {
        Row: {
          assembly_id: string
          byte_count: number | null
          clips: Json
          created_at: string
          exported_at: string
          file_path: string | null
          format: string
          id: string
          version: number
        }
        Insert: {
          assembly_id: string
          byte_count?: number | null
          clips?: Json
          created_at?: string
          exported_at?: string
          file_path?: string | null
          format: string
          id?: string
          version: number
        }
        Update: {
          assembly_id?: string
          byte_count?: number | null
          clips?: Json
          created_at?: string
          exported_at?: string
          file_path?: string | null
          format?: string
          id?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "assembly_versions_assembly_id_fkey"
            columns: ["assembly_id"]
            isOneToOne: false
            referencedRelation: "assemblies"
            referencedColumns: ["id"]
          },
        ]
      }
      clips: {
        Row: {
          ai_scores: Json | null
          ai_scores_processed_at: string | null
          approval_status: Json
          audio_channels: number
          audio_sample_rate: number
          camera_angle: string | null
          camera_group_id: string | null
          checksum: string
          created_at: string
          duration_seconds: number
          file_path: string
          file_size: number
          flags: Json
          format: Json
          frame_rate: number
          hierarchy: Json
          id: string
          metadata: Json
          project_id: string
          proxy_color_space: string | null
          proxy_generated_at: string | null
          proxy_lut: string | null
          proxy_r2_key: string | null
          proxy_status: string
          resolution: Json
          review_status: string
          sync_confidence: number | null
          sync_offset_frames: number | null
          sync_processed_at: string | null
          sync_status: string
          timecode_source: string
          timecode_start: string
          transcription_language: string | null
          transcription_processed_at: string | null
          transcription_status: string
          transcription_text: string | null
          updated_at: string
        }
        Insert: {
          ai_scores?: Json | null
          ai_scores_processed_at?: string | null
          approval_status?: Json
          audio_channels: number
          audio_sample_rate: number
          camera_angle?: string | null
          camera_group_id?: string | null
          checksum: string
          created_at?: string
          duration_seconds: number
          file_path: string
          file_size: number
          flags?: Json
          format: Json
          frame_rate: number
          hierarchy: Json
          id?: string
          metadata?: Json
          project_id: string
          proxy_color_space?: string | null
          proxy_generated_at?: string | null
          proxy_lut?: string | null
          proxy_r2_key?: string | null
          proxy_status?: string
          resolution: Json
          review_status?: string
          sync_confidence?: number | null
          sync_offset_frames?: number | null
          sync_processed_at?: string | null
          sync_status?: string
          timecode_source: string
          timecode_start: string
          transcription_language?: string | null
          transcription_processed_at?: string | null
          transcription_status?: string
          transcription_text?: string | null
          updated_at?: string
        }
        Update: {
          ai_scores?: Json | null
          ai_scores_processed_at?: string | null
          approval_status?: Json
          audio_channels?: number
          audio_sample_rate?: number
          camera_angle?: string | null
          camera_group_id?: string | null
          checksum?: string
          created_at?: string
          duration_seconds?: number
          file_path?: string
          file_size?: number
          flags?: Json
          format?: Json
          frame_rate?: number
          hierarchy?: Json
          id?: string
          metadata?: Json
          project_id?: string
          proxy_color_space?: string | null
          proxy_generated_at?: string | null
          proxy_lut?: string | null
          proxy_r2_key?: string | null
          proxy_status?: string
          resolution?: Json
          review_status?: string
          sync_confidence?: number | null
          sync_offset_frames?: number | null
          sync_processed_at?: string | null
          sync_status?: string
          timecode_source?: string
          timecode_start?: string
          transcription_language?: string | null
          transcription_processed_at?: string | null
          transcription_status?: string
          transcription_text?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "clips_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      locations: {
        Row: {
          created_at: string
          id: string
          name: string
          project_id: string
          type: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          project_id: string
          type: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          project_id?: string
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "locations_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      project_crew: {
        Row: {
          created_at: string
          email: string
          id: string
          name: string
          project_id: string
          role: string
          user_id: string
        }
        Insert: {
          created_at?: string
          email: string
          id?: string
          name: string
          project_id: string
          role: string
          user_id: string
        }
        Update: {
          created_at?: string
          email?: string
          id?: string
          name?: string
          project_id?: string
          role?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "project_crew_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      projects: {
        Row: {
          created_at: string
          id: string
          mode: string
          name: string
          settings: Json
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          mode: string
          name: string
          settings?: Json
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          mode?: string
          name?: string
          settings?: Json
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      share_links: {
        Row: {
          created_at: string
          created_by: string
          expires_at: string
          id: string
          last_viewed_at: string | null
          notify_email: string | null
          password_hash: string | null
          permissions: Json
          project_id: string
          revoked_at: string | null
          scope: string
          scope_id: string | null
          token: string
          view_count: number
        }
        Insert: {
          created_at?: string
          created_by: string
          expires_at: string
          id?: string
          last_viewed_at?: string | null
          notify_email?: string | null
          password_hash?: string | null
          permissions?: Json
          project_id: string
          revoked_at?: string | null
          scope: string
          scope_id?: string | null
          token: string
          view_count?: number
        }
        Update: {
          created_at?: string
          created_by?: string
          expires_at?: string
          id?: string
          last_viewed_at?: string | null
          notify_email?: string | null
          password_hash?: string | null
          permissions?: Json
          project_id?: string
          revoked_at?: string | null
          scope?: string
          scope_id?: string | null
          token?: string
          view_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "share_links_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      show_limit: { Args: never; Returns: number }
      show_trgm: { Args: { "": string }; Returns: string[] }
      smpte_to_seconds: { Args: { timecode: string }; Returns: number }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
