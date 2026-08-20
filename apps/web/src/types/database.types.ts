export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      audit_logs: {
        Row: {
          action: string
          actor_user_id: string | null
          company_id: string
          entity_id: string | null
          entity_type: string
          id: string
          metadata: Json
          occurred_at: string
          warehouse_id: string | null
        }
        Insert: {
          action: string
          actor_user_id?: string | null
          company_id: string
          entity_id?: string | null
          entity_type: string
          id?: string
          metadata?: Json
          occurred_at?: string
          warehouse_id?: string | null
        }
        Update: {
          action?: string
          actor_user_id?: string | null
          company_id?: string
          entity_id?: string | null
          entity_type?: string
          id?: string
          metadata?: Json
          occurred_at?: string
          warehouse_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_logs_actor_user_id_fkey"
            columns: ["actor_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "audit_logs_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "audit_logs_warehouse_company_fkey"
            columns: ["warehouse_id", "company_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id", "company_id"]
          },
        ]
      }
      brands: {
        Row: {
          company_id: string
          created_at: string
          id: string
          name: string
          normalized_name: string | null
          status: Database["public"]["Enums"]["record_status"]
          updated_at: string
        }
        Insert: {
          company_id: string
          created_at?: string
          id?: string
          name: string
          normalized_name?: string | null
          status?: Database["public"]["Enums"]["record_status"]
          updated_at?: string
        }
        Update: {
          company_id?: string
          created_at?: string
          id?: string
          name?: string
          normalized_name?: string | null
          status?: Database["public"]["Enums"]["record_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "brands_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      companies: {
        Row: {
          created_at: string
          id: string
          name: string
          status: Database["public"]["Enums"]["record_status"]
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          status?: Database["public"]["Enums"]["record_status"]
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          status?: Database["public"]["Enums"]["record_status"]
          updated_at?: string
        }
        Relationships: []
      }
      company_memberships: {
        Row: {
          company_id: string
          created_at: string
          id: string
          role: Database["public"]["Enums"]["membership_role"]
          status: Database["public"]["Enums"]["record_status"]
          updated_at: string
          user_id: string
        }
        Insert: {
          company_id: string
          created_at?: string
          id?: string
          role: Database["public"]["Enums"]["membership_role"]
          status?: Database["public"]["Enums"]["record_status"]
          updated_at?: string
          user_id: string
        }
        Update: {
          company_id?: string
          created_at?: string
          id?: string
          role?: Database["public"]["Enums"]["membership_role"]
          status?: Database["public"]["Enums"]["record_status"]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "company_memberships_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_memberships_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["user_id"]
          },
        ]
      }
      company_settings: {
        Row: {
          company_id: string
          created_at: string
          default_variance_threshold_units: number
          recognition_high_confidence: number
          recognition_medium_confidence: number
          reopen_window_days: number
          updated_at: string
        }
        Insert: {
          company_id: string
          created_at?: string
          default_variance_threshold_units?: number
          recognition_high_confidence?: number
          recognition_medium_confidence?: number
          reopen_window_days?: number
          updated_at?: string
        }
        Update: {
          company_id?: string
          created_at?: string
          default_variance_threshold_units?: number
          recognition_high_confidence?: number
          recognition_medium_confidence?: number
          reopen_window_days?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "company_settings_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: true
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      count_flags: {
        Row: {
          company_id: string
          count_id: string
          created_at: string
          flag_type: Database["public"]["Enums"]["count_flag_type"]
          id: string
          resolution_note: string | null
          resolved_at: string | null
          resolved_by: string | null
          status: Database["public"]["Enums"]["count_flag_status"]
          stock_take_id: string
          warehouse_id: string
        }
        Insert: {
          company_id: string
          count_id: string
          created_at?: string
          flag_type: Database["public"]["Enums"]["count_flag_type"]
          id?: string
          resolution_note?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          status?: Database["public"]["Enums"]["count_flag_status"]
          stock_take_id: string
          warehouse_id: string
        }
        Update: {
          company_id?: string
          count_id?: string
          created_at?: string
          flag_type?: Database["public"]["Enums"]["count_flag_type"]
          id?: string
          resolution_note?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          status?: Database["public"]["Enums"]["count_flag_status"]
          stock_take_id?: string
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "count_flags_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "count_flags_company_resolver_fkey"
            columns: ["company_id", "resolved_by"]
            isOneToOne: false
            referencedRelation: "company_memberships"
            referencedColumns: ["company_id", "user_id"]
          },
          {
            foreignKeyName: "count_flags_count_scope_fkey"
            columns: ["count_id", "company_id", "warehouse_id", "stock_take_id"]
            isOneToOne: false
            referencedRelation: "counts"
            referencedColumns: [
              "id",
              "company_id",
              "warehouse_id",
              "stock_take_id",
            ]
          },
        ]
      }
      counts: {
        Row: {
          cases: number
          company_id: string
          count_type: Database["public"]["Enums"]["count_type"]
          duration_ms: number | null
          id: string
          idempotency_key: string
          layers: number
          pallets: number
          product_id: string
          stock_take_id: string
          stock_taker_session_id: string
          submitted_at: string
          submitted_by: string
          total_units: number
          units: number
          warehouse_id: string
        }
        Insert: {
          cases: number
          company_id: string
          count_type: Database["public"]["Enums"]["count_type"]
          duration_ms?: number | null
          id?: string
          idempotency_key: string
          layers: number
          pallets: number
          product_id: string
          stock_take_id: string
          stock_taker_session_id: string
          submitted_at?: string
          submitted_by: string
          total_units: number
          units: number
          warehouse_id: string
        }
        Update: {
          cases?: number
          company_id?: string
          count_type?: Database["public"]["Enums"]["count_type"]
          duration_ms?: number | null
          id?: string
          idempotency_key?: string
          layers?: number
          pallets?: number
          product_id?: string
          stock_take_id?: string
          stock_taker_session_id?: string
          submitted_at?: string
          submitted_by?: string
          total_units?: number
          units?: number
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "counts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "counts_company_submitter_fkey"
            columns: ["company_id", "submitted_by"]
            isOneToOne: false
            referencedRelation: "company_memberships"
            referencedColumns: ["company_id", "user_id"]
          },
          {
            foreignKeyName: "counts_product_company_fkey"
            columns: ["product_id", "company_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "company_id"]
          },
          {
            foreignKeyName: "counts_session_scope_fkey"
            columns: [
              "stock_taker_session_id",
              "company_id",
              "warehouse_id",
              "stock_take_id",
            ]
            isOneToOne: false
            referencedRelation: "stock_taker_sessions"
            referencedColumns: [
              "id",
              "company_id",
              "warehouse_id",
              "stock_take_id",
            ]
          },
          {
            foreignKeyName: "counts_stock_take_scope_fkey"
            columns: ["stock_take_id", "company_id", "warehouse_id"]
            isOneToOne: false
            referencedRelation: "stock_takes"
            referencedColumns: ["id", "company_id", "warehouse_id"]
          },
        ]
      }
      import_issues: {
        Row: {
          company_id: string
          created_at: string
          disposition: Database["public"]["Enums"]["import_issue_disposition"]
          field_name: string | null
          id: string
          import_job_id: string
          issue_code: string
          message: string
          raw_row: Json
          row_number: number
          stock_take_id: string | null
          warehouse_id: string | null
        }
        Insert: {
          company_id: string
          created_at?: string
          disposition: Database["public"]["Enums"]["import_issue_disposition"]
          field_name?: string | null
          id?: string
          import_job_id: string
          issue_code: string
          message: string
          raw_row: Json
          row_number: number
          stock_take_id?: string | null
          warehouse_id?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          disposition?: Database["public"]["Enums"]["import_issue_disposition"]
          field_name?: string | null
          id?: string
          import_job_id?: string
          issue_code?: string
          message?: string
          raw_row?: Json
          row_number?: number
          stock_take_id?: string | null
          warehouse_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "import_issues_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "import_issues_job_company_fkey"
            columns: ["import_job_id", "company_id"]
            isOneToOne: false
            referencedRelation: "import_jobs"
            referencedColumns: ["id", "company_id"]
          },
          {
            foreignKeyName: "import_issues_stock_take_scope_fkey"
            columns: ["stock_take_id", "company_id", "warehouse_id"]
            isOneToOne: false
            referencedRelation: "stock_takes"
            referencedColumns: ["id", "company_id", "warehouse_id"]
          },
          {
            foreignKeyName: "import_issues_warehouse_company_fkey"
            columns: ["warehouse_id", "company_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id", "company_id"]
          },
        ]
      }
      import_jobs: {
        Row: {
          accepted_rows: number
          column_mapping: Json
          company_id: string
          completed_at: string | null
          created_by: string
          flagged_rows: number
          id: string
          kind: Database["public"]["Enums"]["import_kind"]
          rejected_rows: number
          snapshot_as_of: string | null
          source_filename: string
          source_metadata: Json
          source_sha256: string | null
          started_at: string
          status: Database["public"]["Enums"]["import_job_status"]
          stock_take_id: string | null
          total_rows: number
          warehouse_id: string | null
        }
        Insert: {
          accepted_rows?: number
          column_mapping: Json
          company_id: string
          completed_at?: string | null
          created_by: string
          flagged_rows?: number
          id?: string
          kind: Database["public"]["Enums"]["import_kind"]
          rejected_rows?: number
          snapshot_as_of?: string | null
          source_filename: string
          source_metadata?: Json
          source_sha256?: string | null
          started_at?: string
          status?: Database["public"]["Enums"]["import_job_status"]
          stock_take_id?: string | null
          total_rows?: number
          warehouse_id?: string | null
        }
        Update: {
          accepted_rows?: number
          column_mapping?: Json
          company_id?: string
          completed_at?: string | null
          created_by?: string
          flagged_rows?: number
          id?: string
          kind?: Database["public"]["Enums"]["import_kind"]
          rejected_rows?: number
          snapshot_as_of?: string | null
          source_filename?: string
          source_metadata?: Json
          source_sha256?: string | null
          started_at?: string
          status?: Database["public"]["Enums"]["import_job_status"]
          stock_take_id?: string | null
          total_rows?: number
          warehouse_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "import_jobs_company_creator_fkey"
            columns: ["company_id", "created_by"]
            isOneToOne: false
            referencedRelation: "company_memberships"
            referencedColumns: ["company_id", "user_id"]
          },
          {
            foreignKeyName: "import_jobs_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "import_jobs_stock_take_scope_fkey"
            columns: ["stock_take_id", "company_id", "warehouse_id"]
            isOneToOne: false
            referencedRelation: "stock_takes"
            referencedColumns: ["id", "company_id", "warehouse_id"]
          },
          {
            foreignKeyName: "import_jobs_warehouse_company_fkey"
            columns: ["warehouse_id", "company_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id", "company_id"]
          },
        ]
      }
      product_warehouse_settings: {
        Row: {
          company_id: string
          created_at: string
          id: string
          product_id: string
          updated_at: string
          updated_by: string | null
          variance_threshold_active: boolean
          variance_threshold_units: number
          warehouse_id: string
        }
        Insert: {
          company_id: string
          created_at?: string
          id?: string
          product_id: string
          updated_at?: string
          updated_by?: string | null
          variance_threshold_active?: boolean
          variance_threshold_units?: number
          warehouse_id: string
        }
        Update: {
          company_id?: string
          created_at?: string
          id?: string
          product_id?: string
          updated_at?: string
          updated_by?: string | null
          variance_threshold_active?: boolean
          variance_threshold_units?: number
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "product_warehouse_settings_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "product_warehouse_settings_company_updater_fkey"
            columns: ["company_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "company_memberships"
            referencedColumns: ["company_id", "user_id"]
          },
          {
            foreignKeyName: "product_warehouse_settings_product_scope_fkey"
            columns: ["product_id", "company_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "company_id"]
          },
          {
            foreignKeyName: "product_warehouse_settings_warehouse_scope_fkey"
            columns: ["warehouse_id", "company_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id", "company_id"]
          },
        ]
      }
      products: {
        Row: {
          barcode: string | null
          brand_id: string | null
          cases_per_layer: number | null
          cases_per_pallet: number | null
          company_id: string
          created_at: string
          id: string
          name: string
          normalized_barcode: string | null
          normalized_name: string | null
          normalized_product_code: string | null
          product_code: string
          status: Database["public"]["Enums"]["record_status"]
          units_per_case: number | null
          updated_at: string
        }
        Insert: {
          barcode?: string | null
          brand_id?: string | null
          cases_per_layer?: number | null
          cases_per_pallet?: number | null
          company_id: string
          created_at?: string
          id?: string
          name: string
          normalized_barcode?: string | null
          normalized_name?: string | null
          normalized_product_code?: string | null
          product_code: string
          status?: Database["public"]["Enums"]["record_status"]
          units_per_case?: number | null
          updated_at?: string
        }
        Update: {
          barcode?: string | null
          brand_id?: string | null
          cases_per_layer?: number | null
          cases_per_pallet?: number | null
          company_id?: string
          created_at?: string
          id?: string
          name?: string
          normalized_barcode?: string | null
          normalized_name?: string | null
          normalized_product_code?: string | null
          product_code?: string
          status?: Database["public"]["Enums"]["record_status"]
          units_per_case?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "products_brand_company_fkey"
            columns: ["brand_id", "company_id"]
            isOneToOne: false
            referencedRelation: "brands"
            referencedColumns: ["id", "company_id"]
          },
          {
            foreignKeyName: "products_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          created_at: string
          display_name: string
          platform_role: Database["public"]["Enums"]["platform_role"] | null
          status: Database["public"]["Enums"]["record_status"]
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          display_name: string
          platform_role?: Database["public"]["Enums"]["platform_role"] | null
          status?: Database["public"]["Enums"]["record_status"]
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          display_name?: string
          platform_role?: Database["public"]["Enums"]["platform_role"] | null
          status?: Database["public"]["Enums"]["record_status"]
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      recognition_events: {
        Row: {
          candidate_products: Json
          captured_at: string
          cleaned_at: string | null
          cleanup_attempts: number
          cleanup_error: string | null
          company_id: string
          confidence: number | null
          confidence_tier: Database["public"]["Enums"]["recognition_confidence_tier"]
          created_at: string
          id: string
          idempotency_key: string
          last_cleanup_attempt_at: string | null
          media_bucket: string | null
          media_expires_at: string | null
          media_path: string | null
          media_status: Database["public"]["Enums"]["recognition_media_status"]
          model: string
          next_cleanup_at: string | null
          provider: string
          recognized_at: string
          selected_at: string | null
          selected_product_id: string | null
          selection_method: Database["public"]["Enums"]["recognition_selection_method"]
          stock_take_id: string
          stock_taker_session_id: string
          user_id: string
          warehouse_id: string
        }
        Insert: {
          candidate_products?: Json
          captured_at: string
          cleaned_at?: string | null
          cleanup_attempts?: number
          cleanup_error?: string | null
          company_id: string
          confidence?: number | null
          confidence_tier: Database["public"]["Enums"]["recognition_confidence_tier"]
          created_at?: string
          id?: string
          idempotency_key: string
          last_cleanup_attempt_at?: string | null
          media_bucket?: string | null
          media_expires_at?: string | null
          media_path?: string | null
          media_status?: Database["public"]["Enums"]["recognition_media_status"]
          model: string
          next_cleanup_at?: string | null
          provider: string
          recognized_at?: string
          selected_at?: string | null
          selected_product_id?: string | null
          selection_method?: Database["public"]["Enums"]["recognition_selection_method"]
          stock_take_id: string
          stock_taker_session_id: string
          user_id: string
          warehouse_id: string
        }
        Update: {
          candidate_products?: Json
          captured_at?: string
          cleaned_at?: string | null
          cleanup_attempts?: number
          cleanup_error?: string | null
          company_id?: string
          confidence?: number | null
          confidence_tier?: Database["public"]["Enums"]["recognition_confidence_tier"]
          created_at?: string
          id?: string
          idempotency_key?: string
          last_cleanup_attempt_at?: string | null
          media_bucket?: string | null
          media_expires_at?: string | null
          media_path?: string | null
          media_status?: Database["public"]["Enums"]["recognition_media_status"]
          model?: string
          next_cleanup_at?: string | null
          provider?: string
          recognized_at?: string
          selected_at?: string | null
          selected_product_id?: string | null
          selection_method?: Database["public"]["Enums"]["recognition_selection_method"]
          stock_take_id?: string
          stock_taker_session_id?: string
          user_id?: string
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "recognition_events_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recognition_events_company_user_fkey"
            columns: ["company_id", "user_id"]
            isOneToOne: false
            referencedRelation: "company_memberships"
            referencedColumns: ["company_id", "user_id"]
          },
          {
            foreignKeyName: "recognition_events_selected_product_fkey"
            columns: ["selected_product_id", "company_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "company_id"]
          },
          {
            foreignKeyName: "recognition_events_session_scope_fkey"
            columns: [
              "stock_taker_session_id",
              "company_id",
              "warehouse_id",
              "stock_take_id",
            ]
            isOneToOne: false
            referencedRelation: "stock_taker_sessions"
            referencedColumns: [
              "id",
              "company_id",
              "warehouse_id",
              "stock_take_id",
            ]
          },
          {
            foreignKeyName: "recognition_events_stock_take_scope_fkey"
            columns: ["stock_take_id", "company_id", "warehouse_id"]
            isOneToOne: false
            referencedRelation: "stock_takes"
            referencedColumns: ["id", "company_id", "warehouse_id"]
          },
        ]
      }
      recount_batches: {
        Row: {
          company_id: string
          completed_at: string | null
          created_at: string
          created_by: string
          id: string
          minimum_absolute_variance_units: number | null
          status: Database["public"]["Enums"]["recount_batch_status"]
          stock_take_id: string
          warehouse_id: string
        }
        Insert: {
          company_id: string
          completed_at?: string | null
          created_at?: string
          created_by: string
          id?: string
          minimum_absolute_variance_units?: number | null
          status?: Database["public"]["Enums"]["recount_batch_status"]
          stock_take_id: string
          warehouse_id: string
        }
        Update: {
          company_id?: string
          completed_at?: string | null
          created_at?: string
          created_by?: string
          id?: string
          minimum_absolute_variance_units?: number | null
          status?: Database["public"]["Enums"]["recount_batch_status"]
          stock_take_id?: string
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "recount_batches_company_creator_fkey"
            columns: ["company_id", "created_by"]
            isOneToOne: false
            referencedRelation: "company_memberships"
            referencedColumns: ["company_id", "user_id"]
          },
          {
            foreignKeyName: "recount_batches_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recount_batches_stock_take_scope_fkey"
            columns: ["stock_take_id", "company_id", "warehouse_id"]
            isOneToOne: false
            referencedRelation: "stock_takes"
            referencedColumns: ["id", "company_id", "warehouse_id"]
          },
        ]
      }
      recount_counts: {
        Row: {
          cases: number
          company_id: string
          duration_ms: number | null
          id: string
          idempotency_key: string
          layers: number
          pallets: number
          product_id: string
          recount_task_id: string
          stock_take_id: string
          stock_taker_session_id: string
          submitted_at: string
          submitted_by: string
          total_units: number
          units: number
          warehouse_id: string
        }
        Insert: {
          cases: number
          company_id: string
          duration_ms?: number | null
          id?: string
          idempotency_key: string
          layers: number
          pallets: number
          product_id: string
          recount_task_id: string
          stock_take_id: string
          stock_taker_session_id: string
          submitted_at?: string
          submitted_by: string
          total_units: number
          units: number
          warehouse_id: string
        }
        Update: {
          cases?: number
          company_id?: string
          duration_ms?: number | null
          id?: string
          idempotency_key?: string
          layers?: number
          pallets?: number
          product_id?: string
          recount_task_id?: string
          stock_take_id?: string
          stock_taker_session_id?: string
          submitted_at?: string
          submitted_by?: string
          total_units?: number
          units?: number
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "recount_counts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recount_counts_company_submitter_fkey"
            columns: ["company_id", "submitted_by"]
            isOneToOne: false
            referencedRelation: "company_memberships"
            referencedColumns: ["company_id", "user_id"]
          },
          {
            foreignKeyName: "recount_counts_product_scope_fkey"
            columns: ["product_id", "company_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "company_id"]
          },
          {
            foreignKeyName: "recount_counts_session_scope_fkey"
            columns: [
              "stock_taker_session_id",
              "company_id",
              "warehouse_id",
              "stock_take_id",
            ]
            isOneToOne: false
            referencedRelation: "stock_taker_sessions"
            referencedColumns: [
              "id",
              "company_id",
              "warehouse_id",
              "stock_take_id",
            ]
          },
          {
            foreignKeyName: "recount_counts_task_scope_fkey"
            columns: [
              "recount_task_id",
              "company_id",
              "warehouse_id",
              "stock_take_id",
              "product_id",
            ]
            isOneToOne: false
            referencedRelation: "recount_tasks"
            referencedColumns: [
              "id",
              "company_id",
              "warehouse_id",
              "stock_take_id",
              "product_id",
            ]
          },
        ]
      }
      recount_tasks: {
        Row: {
          assigned_user_id: string | null
          assignment_role: Database["public"]["Enums"]["membership_role"]
          brand_id: string | null
          claim_role: Database["public"]["Enums"]["membership_role"]
          claimed_at: string | null
          claimed_by: string | null
          company_id: string
          completed_at: string | null
          created_at: string
          effective_threshold_units: number
          id: string
          product_id: string
          recount_batch_id: string
          source_absolute_variance_units: number
          source_physical_units: number
          source_signed_variance_units: number
          status: Database["public"]["Enums"]["recount_task_status"]
          stock_take_id: string
          threshold_source: Database["public"]["Enums"]["variance_threshold_source"]
          warehouse_id: string
        }
        Insert: {
          assigned_user_id?: string | null
          assignment_role?: Database["public"]["Enums"]["membership_role"]
          brand_id?: string | null
          claim_role?: Database["public"]["Enums"]["membership_role"]
          claimed_at?: string | null
          claimed_by?: string | null
          company_id: string
          completed_at?: string | null
          created_at?: string
          effective_threshold_units: number
          id?: string
          product_id: string
          recount_batch_id: string
          source_absolute_variance_units: number
          source_physical_units: number
          source_signed_variance_units: number
          status?: Database["public"]["Enums"]["recount_task_status"]
          stock_take_id: string
          threshold_source: Database["public"]["Enums"]["variance_threshold_source"]
          warehouse_id: string
        }
        Update: {
          assigned_user_id?: string | null
          assignment_role?: Database["public"]["Enums"]["membership_role"]
          brand_id?: string | null
          claim_role?: Database["public"]["Enums"]["membership_role"]
          claimed_at?: string | null
          claimed_by?: string | null
          company_id?: string
          completed_at?: string | null
          created_at?: string
          effective_threshold_units?: number
          id?: string
          product_id?: string
          recount_batch_id?: string
          source_absolute_variance_units?: number
          source_physical_units?: number
          source_signed_variance_units?: number
          status?: Database["public"]["Enums"]["recount_task_status"]
          stock_take_id?: string
          threshold_source?: Database["public"]["Enums"]["variance_threshold_source"]
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "recount_tasks_assigned_membership_fkey"
            columns: [
              "company_id",
              "warehouse_id",
              "assigned_user_id",
              "assignment_role",
            ]
            isOneToOne: false
            referencedRelation: "warehouse_memberships"
            referencedColumns: ["company_id", "warehouse_id", "user_id", "role"]
          },
          {
            foreignKeyName: "recount_tasks_batch_scope_fkey"
            columns: [
              "recount_batch_id",
              "company_id",
              "warehouse_id",
              "stock_take_id",
            ]
            isOneToOne: false
            referencedRelation: "recount_batches"
            referencedColumns: [
              "id",
              "company_id",
              "warehouse_id",
              "stock_take_id",
            ]
          },
          {
            foreignKeyName: "recount_tasks_brand_scope_fkey"
            columns: ["brand_id", "company_id"]
            isOneToOne: false
            referencedRelation: "brands"
            referencedColumns: ["id", "company_id"]
          },
          {
            foreignKeyName: "recount_tasks_claimed_membership_fkey"
            columns: ["company_id", "warehouse_id", "claimed_by", "claim_role"]
            isOneToOne: false
            referencedRelation: "warehouse_memberships"
            referencedColumns: ["company_id", "warehouse_id", "user_id", "role"]
          },
          {
            foreignKeyName: "recount_tasks_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recount_tasks_product_scope_fkey"
            columns: ["product_id", "company_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "company_id"]
          },
        ]
      }
      stock_snapshot_lines: {
        Row: {
          company_id: string
          created_at: string
          id: string
          import_job_id: string
          product_id: string
          quantity_on_hand: number
          snapshot_as_of: string
          source_row: Json
          source_row_number: number
          stock_take_id: string
          warehouse_id: string
        }
        Insert: {
          company_id: string
          created_at?: string
          id?: string
          import_job_id: string
          product_id: string
          quantity_on_hand: number
          snapshot_as_of: string
          source_row: Json
          source_row_number: number
          stock_take_id: string
          warehouse_id: string
        }
        Update: {
          company_id?: string
          created_at?: string
          id?: string
          import_job_id?: string
          product_id?: string
          quantity_on_hand?: number
          snapshot_as_of?: string
          source_row?: Json
          source_row_number?: number
          stock_take_id?: string
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "stock_snapshot_lines_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_snapshot_lines_import_job_scope_fkey"
            columns: [
              "import_job_id",
              "company_id",
              "warehouse_id",
              "stock_take_id",
            ]
            isOneToOne: false
            referencedRelation: "import_jobs"
            referencedColumns: [
              "id",
              "company_id",
              "warehouse_id",
              "stock_take_id",
            ]
          },
          {
            foreignKeyName: "stock_snapshot_lines_product_company_fkey"
            columns: ["product_id", "company_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id", "company_id"]
          },
          {
            foreignKeyName: "stock_snapshot_lines_stock_take_scope_fkey"
            columns: ["stock_take_id", "company_id", "warehouse_id"]
            isOneToOne: false
            referencedRelation: "stock_takes"
            referencedColumns: ["id", "company_id", "warehouse_id"]
          },
        ]
      }
      stock_take_exports: {
        Row: {
          company_id: string
          created_at: string
          created_by: string
          export_format: string
          export_kind: string
          filename: string
          id: string
          metadata: Json
          row_count: number
          stock_take_id: string
          warehouse_id: string
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by: string
          export_format?: string
          export_kind: string
          filename: string
          id?: string
          metadata?: Json
          row_count: number
          stock_take_id: string
          warehouse_id: string
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string
          export_format?: string
          export_kind?: string
          filename?: string
          id?: string
          metadata?: Json
          row_count?: number
          stock_take_id?: string
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "stock_take_exports_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_take_exports_creator_fkey"
            columns: ["company_id", "created_by"]
            isOneToOne: false
            referencedRelation: "company_memberships"
            referencedColumns: ["company_id", "user_id"]
          },
          {
            foreignKeyName: "stock_take_exports_stock_take_scope_fkey"
            columns: ["stock_take_id", "company_id", "warehouse_id"]
            isOneToOne: false
            referencedRelation: "stock_takes"
            referencedColumns: ["id", "company_id", "warehouse_id"]
          },
        ]
      }
      stock_taker_sessions: {
        Row: {
          company_id: string
          created_at: string
          ended_at: string | null
          id: string
          last_active_at: string
          membership_role: Database["public"]["Enums"]["membership_role"]
          started_at: string
          status: Database["public"]["Enums"]["stock_taker_session_status"]
          stock_take_id: string
          updated_at: string
          user_id: string
          warehouse_id: string
        }
        Insert: {
          company_id: string
          created_at?: string
          ended_at?: string | null
          id?: string
          last_active_at?: string
          membership_role?: Database["public"]["Enums"]["membership_role"]
          started_at?: string
          status?: Database["public"]["Enums"]["stock_taker_session_status"]
          stock_take_id: string
          updated_at?: string
          user_id: string
          warehouse_id: string
        }
        Update: {
          company_id?: string
          created_at?: string
          ended_at?: string | null
          id?: string
          last_active_at?: string
          membership_role?: Database["public"]["Enums"]["membership_role"]
          started_at?: string
          status?: Database["public"]["Enums"]["stock_taker_session_status"]
          stock_take_id?: string
          updated_at?: string
          user_id?: string
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "stock_taker_sessions_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_taker_sessions_membership_fkey"
            columns: [
              "company_id",
              "warehouse_id",
              "user_id",
              "membership_role",
            ]
            isOneToOne: false
            referencedRelation: "warehouse_memberships"
            referencedColumns: ["company_id", "warehouse_id", "user_id", "role"]
          },
          {
            foreignKeyName: "stock_taker_sessions_stock_take_scope_fkey"
            columns: ["stock_take_id", "company_id", "warehouse_id"]
            isOneToOne: false
            referencedRelation: "stock_takes"
            referencedColumns: ["id", "company_id", "warehouse_id"]
          },
        ]
      }
      stock_takes: {
        Row: {
          company_id: string
          completed_at: string | null
          completed_by: string | null
          completion_mode: string | null
          completion_reason: string | null
          created_at: string
          created_by: string
          id: string
          ready_at: string | null
          reopen_count: number
          reopen_reason: string | null
          reopened_at: string | null
          reopened_by: string | null
          started_at: string | null
          status: Database["public"]["Enums"]["stock_take_status"]
          updated_at: string
          warehouse_id: string
        }
        Insert: {
          company_id: string
          completed_at?: string | null
          completed_by?: string | null
          completion_mode?: string | null
          completion_reason?: string | null
          created_at?: string
          created_by: string
          id?: string
          ready_at?: string | null
          reopen_count?: number
          reopen_reason?: string | null
          reopened_at?: string | null
          reopened_by?: string | null
          started_at?: string | null
          status?: Database["public"]["Enums"]["stock_take_status"]
          updated_at?: string
          warehouse_id: string
        }
        Update: {
          company_id?: string
          completed_at?: string | null
          completed_by?: string | null
          completion_mode?: string | null
          completion_reason?: string | null
          created_at?: string
          created_by?: string
          id?: string
          ready_at?: string | null
          reopen_count?: number
          reopen_reason?: string | null
          reopened_at?: string | null
          reopened_by?: string | null
          started_at?: string | null
          status?: Database["public"]["Enums"]["stock_take_status"]
          updated_at?: string
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "stock_takes_company_completed_by_fkey"
            columns: ["company_id", "completed_by"]
            isOneToOne: false
            referencedRelation: "company_memberships"
            referencedColumns: ["company_id", "user_id"]
          },
          {
            foreignKeyName: "stock_takes_company_creator_fkey"
            columns: ["company_id", "created_by"]
            isOneToOne: false
            referencedRelation: "company_memberships"
            referencedColumns: ["company_id", "user_id"]
          },
          {
            foreignKeyName: "stock_takes_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_takes_company_reopened_by_fkey"
            columns: ["company_id", "reopened_by"]
            isOneToOne: false
            referencedRelation: "company_memberships"
            referencedColumns: ["company_id", "user_id"]
          },
          {
            foreignKeyName: "stock_takes_warehouse_company_fkey"
            columns: ["warehouse_id", "company_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id", "company_id"]
          },
        ]
      }
      warehouse_memberships: {
        Row: {
          company_id: string
          created_at: string
          id: string
          role: Database["public"]["Enums"]["membership_role"]
          status: Database["public"]["Enums"]["record_status"]
          updated_at: string
          user_id: string
          warehouse_id: string
        }
        Insert: {
          company_id: string
          created_at?: string
          id?: string
          role: Database["public"]["Enums"]["membership_role"]
          status?: Database["public"]["Enums"]["record_status"]
          updated_at?: string
          user_id: string
          warehouse_id: string
        }
        Update: {
          company_id?: string
          created_at?: string
          id?: string
          role?: Database["public"]["Enums"]["membership_role"]
          status?: Database["public"]["Enums"]["record_status"]
          updated_at?: string
          user_id?: string
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "warehouse_memberships_company_user_role_fkey"
            columns: ["company_id", "user_id", "role"]
            isOneToOne: false
            referencedRelation: "company_memberships"
            referencedColumns: ["company_id", "user_id", "role"]
          },
          {
            foreignKeyName: "warehouse_memberships_warehouse_company_fkey"
            columns: ["warehouse_id", "company_id"]
            isOneToOne: false
            referencedRelation: "warehouses"
            referencedColumns: ["id", "company_id"]
          },
        ]
      }
      warehouse_settings: {
        Row: {
          company_id: string
          created_at: string
          updated_at: string
          updated_by: string | null
          variance_threshold_active: boolean
          variance_threshold_units: number
          warehouse_id: string
        }
        Insert: {
          company_id: string
          created_at?: string
          updated_at?: string
          updated_by?: string | null
          variance_threshold_active?: boolean
          variance_threshold_units?: number
          warehouse_id: string
        }
        Update: {
          company_id?: string
          created_at?: string
          updated_at?: string
          updated_by?: string | null
          variance_threshold_active?: boolean
          variance_threshold_units?: number
          warehouse_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "warehouse_settings_company_updater_fkey"
            columns: ["company_id", "updated_by"]
            isOneToOne: false
            referencedRelation: "company_memberships"
            referencedColumns: ["company_id", "user_id"]
          },
          {
            foreignKeyName: "warehouse_settings_warehouse_scope_fkey"
            columns: ["warehouse_id", "company_id"]
            isOneToOne: true
            referencedRelation: "warehouses"
            referencedColumns: ["id", "company_id"]
          },
        ]
      }
      warehouses: {
        Row: {
          company_id: string
          created_at: string
          id: string
          name: string
          status: Database["public"]["Enums"]["record_status"]
          updated_at: string
          warehouse_code: string
        }
        Insert: {
          company_id: string
          created_at?: string
          id?: string
          name: string
          status?: Database["public"]["Enums"]["record_status"]
          updated_at?: string
          warehouse_code: string
        }
        Update: {
          company_id?: string
          created_at?: string
          id?: string
          name?: string
          status?: Database["public"]["Enums"]["record_status"]
          updated_at?: string
          warehouse_code?: string
        }
        Relationships: [
          {
            foreignKeyName: "warehouses_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      assign_recount_tasks: {
        Args: {
          p_assigned_user_id?: string
          p_company_id: string
          p_recount_task_ids: string[]
          p_warehouse_id: string
        }
        Returns: Json
      }
      authorize_recognition_cleanup: {
        Args: { p_token: string }
        Returns: boolean
      }
      claim_recognition_media_cleanup: {
        Args: { p_limit?: number }
        Returns: Json
      }
      claim_recount_task: { Args: { p_recount_task_id: string }; Returns: Json }
      complete_recognition_media_cleanup: {
        Args: {
          p_error?: string
          p_recognition_event_id: string
          p_success: boolean
        }
        Returns: Json
      }
      complete_stock_take: {
        Args: {
          p_company_id: string
          p_stock_take_id: string
          p_warehouse_id: string
        }
        Returns: Json
      }
      confirm_recognition_selection: {
        Args: {
          p_product_id: string
          p_recognition_event_id: string
          p_selection_method: Database["public"]["Enums"]["recognition_selection_method"]
        }
        Returns: Json
      }
      create_recount_batch: {
        Args: {
          p_assigned_user_id?: string
          p_brand_id?: string
          p_company_id: string
          p_minimum_absolute_variance_units?: number
          p_product_id?: string
          p_stock_take_id: string
          p_warehouse_id: string
        }
        Returns: Json
      }
      create_stock_take: {
        Args: { p_company_id: string; p_warehouse_id: string }
        Returns: Json
      }
      create_stock_take_export: {
        Args: {
          p_company_id: string
          p_export_kind?: string
          p_stock_take_id: string
          p_warehouse_id: string
        }
        Returns: Json
      }
      end_stock_taker_session: { Args: { p_session_id: string }; Returns: Json }
      force_complete_stock_take: {
        Args: {
          p_company_id: string
          p_reason: string
          p_stock_take_id: string
          p_warehouse_id: string
        }
        Returns: Json
      }
      get_manager_progress: {
        Args: {
          p_company_id: string
          p_stock_take_id: string
          p_warehouse_id: string
        }
        Returns: Json
      }
      get_recount_work: { Args: never; Returns: Json }
      get_stock_taker_context: { Args: never; Returns: Json }
      get_variances: {
        Args: {
          p_brand_id?: string
          p_company_id: string
          p_minimum_absolute_variance_units?: number
          p_product_id?: string
          p_stock_take_id: string
          p_warehouse_id: string
        }
        Returns: Json
      }
      import_product_master: {
        Args: {
          p_column_mapping: Json
          p_company_id: string
          p_rows: Json
          p_source_filename: string
          p_source_metadata?: Json
          p_source_sha256: string
        }
        Returns: Json
      }
      import_stock_snapshot: {
        Args: {
          p_column_mapping: Json
          p_company_id: string
          p_rows: Json
          p_snapshot_as_of: string
          p_source_filename: string
          p_source_metadata?: Json
          p_source_sha256: string
          p_stock_take_id: string
          p_warehouse_id: string
        }
        Returns: Json
      }
      mark_stock_take_ready: {
        Args: {
          p_company_id: string
          p_stock_take_id: string
          p_warehouse_id: string
        }
        Returns: Json
      }
      move_stock_take_to_review: {
        Args: {
          p_company_id: string
          p_stock_take_id: string
          p_warehouse_id: string
        }
        Returns: Json
      }
      record_recognition_event: { Args: { p_record: Json }; Returns: Json }
      reopen_stock_take: {
        Args: {
          p_company_id: string
          p_reason: string
          p_stock_take_id: string
          p_warehouse_id: string
        }
        Returns: Json
      }
      resolve_count_flag: {
        Args: { p_count_flag_id: string; p_resolution_note: string }
        Returns: Json
      }
      save_product: {
        Args: {
          p_barcode?: string
          p_brand_name?: string
          p_cases_per_layer?: number
          p_cases_per_pallet?: number
          p_company_id: string
          p_name?: string
          p_product_code?: string
          p_product_id?: string
          p_status?: Database["public"]["Enums"]["record_status"]
          p_units_per_case?: number
        }
        Returns: Json
      }
      set_company_variance_threshold: {
        Args: { p_company_id: string; p_threshold_units: number }
        Returns: Json
      }
      set_variance_threshold: {
        Args: {
          p_active?: boolean
          p_company_id: string
          p_product_id?: string
          p_threshold_units: number
          p_warehouse_id: string
        }
        Returns: Json
      }
      start_stock_take: {
        Args: {
          p_company_id: string
          p_stock_take_id: string
          p_warehouse_id: string
        }
        Returns: Json
      }
      start_stock_taker_session: {
        Args: {
          p_company_id: string
          p_stock_take_id: string
          p_warehouse_id: string
        }
        Returns: Json
      }
      submit_count: { Args: { p_record: Json }; Returns: Json }
      submit_recount: { Args: { p_record: Json }; Returns: Json }
      sync_counts_batch: { Args: { p_records: Json }; Returns: Json }
      sync_recognition_events_batch: {
        Args: { p_records: Json }
        Returns: Json
      }
    }
    Enums: {
      count_flag_status: "OPEN" | "RESOLVED"
      count_flag_type: "DUPLICATE_PRODUCT_COUNT_TYPE"
      count_type: "BULK" | "PICK_FACE"
      import_issue_disposition: "flagged" | "rejected"
      import_job_status:
        | "processing"
        | "completed"
        | "completed_with_issues"
        | "failed"
      import_kind: "product_master" | "stock_snapshot"
      membership_role: "super_admin" | "admin" | "manager" | "stock_taker"
      platform_role: "super_admin"
      recognition_confidence_tier: "HIGH" | "MEDIUM" | "LOW" | "NO_MATCH"
      recognition_media_status: "NOT_STORED" | "PENDING" | "DELETED" | "FAILED"
      recognition_selection_method:
        | "AUTO_PRESELECT"
        | "CANDIDATE_CONFIRMATION"
        | "MANUAL_SEARCH"
        | "NO_SELECTION"
      record_status: "active" | "inactive"
      recount_batch_status: "OPEN" | "COMPLETED"
      recount_task_status: "UNASSIGNED" | "ASSIGNED" | "CLAIMED" | "COMPLETED"
      stock_take_status:
        | "DRAFT"
        | "READY"
        | "ACTIVE"
        | "RECOUNT"
        | "REVIEW"
        | "COMPLETED"
        | "REOPENED"
      stock_taker_session_status: "ACTIVE" | "ENDED"
      variance_threshold_source: "COMPANY" | "WAREHOUSE" | "PRODUCT"
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
    Enums: {
      count_flag_status: ["OPEN", "RESOLVED"],
      count_flag_type: ["DUPLICATE_PRODUCT_COUNT_TYPE"],
      count_type: ["BULK", "PICK_FACE"],
      import_issue_disposition: ["flagged", "rejected"],
      import_job_status: [
        "processing",
        "completed",
        "completed_with_issues",
        "failed",
      ],
      import_kind: ["product_master", "stock_snapshot"],
      membership_role: ["super_admin", "admin", "manager", "stock_taker"],
      platform_role: ["super_admin"],
      recognition_confidence_tier: ["HIGH", "MEDIUM", "LOW", "NO_MATCH"],
      recognition_media_status: ["NOT_STORED", "PENDING", "DELETED", "FAILED"],
      recognition_selection_method: [
        "AUTO_PRESELECT",
        "CANDIDATE_CONFIRMATION",
        "MANUAL_SEARCH",
        "NO_SELECTION",
      ],
      record_status: ["active", "inactive"],
      recount_batch_status: ["OPEN", "COMPLETED"],
      recount_task_status: ["UNASSIGNED", "ASSIGNED", "CLAIMED", "COMPLETED"],
      stock_take_status: [
        "DRAFT",
        "READY",
        "ACTIVE",
        "RECOUNT",
        "REVIEW",
        "COMPLETED",
        "REOPENED",
      ],
      stock_taker_session_status: ["ACTIVE", "ENDED"],
      variance_threshold_source: ["COMPANY", "WAREHOUSE", "PRODUCT"],
    },
  },
} as const
