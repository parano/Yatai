-- This adaptation is released under the MIT License.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SEQUENCE epoch_seq INCREMENT BY 1 MAXVALUE 9 CYCLE;
CREATE OR REPLACE FUNCTION generate_object_id() RETURNS varchar AS $$
DECLARE
    time_component bigint;
    epoch_seq int;
    machine_id text := encode(gen_random_bytes(3), 'hex');
    process_id bigint;
    seq_id text := encode(gen_random_bytes(3), 'hex');
    result varchar:= '';
BEGIN
    SELECT FLOOR(EXTRACT(EPOCH FROM clock_timestamp())) INTO time_component;
    SELECT nextval('epoch_seq') INTO epoch_seq;
    SELECT pg_backend_pid() INTO process_id;

    result := result || lpad(to_hex(time_component), 8, '0');
    result := result || machine_id;
    result := result || lpad(to_hex(process_id), 4, '0');
    result := result || seq_id;
    result := result || epoch_seq;
    RETURN result;
END;
$$ LANGUAGE PLPGSQL;

CREATE TYPE "user_perm" AS ENUM ('default', 'admin');
CREATE TYPE "member_role" AS ENUM ('guest', 'developer', 'admin');

CREATE TABLE IF NOT EXISTS "user" (
    id SERIAL PRIMARY KEY,
    uid VARCHAR(32) UNIQUE NOT NULL DEFAULT generate_object_id(),
    perm user_perm NOT NULL DEFAULT 'default',
    name VARCHAR(128) UNIQUE NOT NULL,
    first_name VARCHAR(128) NOT NULL,
    last_name VARCHAR(128) NOT NULL,
    email VARCHAR(256) UNIQUE DEFAULT NULL,
    password VARCHAR(1024) NOT NULL,
    config TEXT DEFAULT '{}',
    github_username VARCHAR(128) UNIQUE DEFAULT NULL,
    is_email_verified BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS "organization" (
    id SERIAL PRIMARY KEY,
    uid VARCHAR(32) UNIQUE NOT NULL DEFAULT generate_object_id(),
    name VARCHAR(128) UNIQUE NOT NULL,
    description TEXT,
    config TEXT DEFAULT '{}',
    creator_id INTEGER NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS "api_token" (
    id SERIAL PRIMARY KEY,
    uid VARCHAR(32) UNIQUE NOT NULL DEFAULT generate_object_id(),
    name VARCHAR(128) NOT NULL,
    description TEXT,
    token VARCHAR(256) UNIQUE NOT NULL,
    scopes TEXT,
    organization_id INTEGER NOT NULL REFERENCES "organization"("id") ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
    last_used_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    expired_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE UNIQUE INDEX "uk_apiToken_organizationId_userId_name" ON "api_token" ("organization_id", "user_id", "name");

CREATE TABLE IF NOT EXISTS "user_group" (
    id SERIAL PRIMARY KEY,
    uid VARCHAR(32) UNIQUE NOT NULL DEFAULT generate_object_id(),
    name VARCHAR(128) NOT NULL,
    organization_id INTEGER NOT NULL REFERENCES "organization"("id") ON DELETE CASCADE,
    creator_id INTEGER NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE UNIQUE INDEX "uk_userGroup_orgId_name" ON "user_group" ("organization_id", "name");

CREATE TABLE IF NOT EXISTS "organization_member" (
    id SERIAL PRIMARY KEY,
    uid VARCHAR(32) UNIQUE NOT NULL DEFAULT generate_object_id(),
    organization_id INTEGER NOT NULL REFERENCES "organization"("id") ON DELETE CASCADE,
    user_group_id INTEGER REFERENCES "user_group"("id") ON DELETE CASCADE,
    user_id INTEGER REFERENCES "user"("id") ON DELETE CASCADE,
    role member_role NOT NULL DEFAULT 'guest',
    creator_id INTEGER NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE UNIQUE INDEX "uk_orgMember_orgId_userGroupId_userId" ON "organization_member" ("organization_id", "user_group_id", "user_id");

CREATE TABLE IF NOT EXISTS "user_group_user_relation" (
    id SERIAL PRIMARY KEY,
    uid VARCHAR(32) UNIQUE NOT NULL DEFAULT generate_object_id(),
    user_group_id INTEGER NOT NULL REFERENCES "user_group"("id") ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
    creator_id INTEGER NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS "cluster" (
    id SERIAL PRIMARY KEY,
    uid VARCHAR(32) UNIQUE NOT NULL DEFAULT generate_object_id(),
    name VARCHAR(128) NOT NULL,
    description TEXT,
    organization_id INTEGER NOT NULL REFERENCES "organization"("id") ON DELETE CASCADE,
    kube_config TEXT NOT NULL,
    config TEXT DEFAULT '{}',
    creator_id INTEGER NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE UNIQUE INDEX "uk_cluster_orgId_name" ON "cluster" ("organization_id", "name");

CREATE TABLE IF NOT EXISTS "cluster_member" (
    id SERIAL PRIMARY KEY,
    uid VARCHAR(32) UNIQUE NOT NULL DEFAULT generate_object_id(),
    cluster_id INTEGER NOT NULL REFERENCES "cluster"("id") ON DELETE CASCADE,
    user_group_id INTEGER REFERENCES "user_group"("id") ON DELETE CASCADE,
    user_id INTEGER REFERENCES "user"("id") ON DELETE CASCADE,
    role member_role NOT NULL DEFAULT 'guest',
    creator_id INTEGER NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE UNIQUE INDEX "uk_clusterMember_userGroupId_userId" ON "cluster_member" ("cluster_id", "user_group_id", "user_id");

CREATE TABLE IF NOT EXISTS "bento_repository" (
    id SERIAL PRIMARY KEY,
    uid VARCHAR(32) UNIQUE NOT NULL DEFAULT generate_object_id(),
    name VARCHAR(128) NOT NULL,
    description TEXT,
    manifest JSONB,
    organization_id INTEGER NOT NULL REFERENCES "organization"("id") ON DELETE CASCADE,
    creator_id INTEGER NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE UNIQUE INDEX "uk_bentoRepository_orgId_name" ON "bento_repository" ("organization_id", "name");

CREATE TYPE "bento_upload_status" AS ENUM ('pending', 'uploading', 'success', 'failed');
CREATE TYPE "bento_image_build_status" AS ENUM ('pending', 'building', 'success', 'failed');

CREATE TABLE IF NOT EXISTS "bento" (
    id SERIAL PRIMARY KEY,
    uid VARCHAR(32) UNIQUE NOT NULL DEFAULT generate_object_id(),
    version VARCHAR(512) NOT NULL,
    description TEXT,
    manifest JSONB,
    file_path TEXT,
    bento_repository_id INTEGER NOT NULL REFERENCES "bento_repository"("id") ON DELETE CASCADE,
    upload_status bento_upload_status NOT NULL DEFAULT 'pending',
    image_build_status bento_image_build_status NOT NULL DEFAULT 'pending',
    image_build_status_syncing_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    image_build_status_updated_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    upload_started_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    upload_finished_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    upload_finished_reason TEXT,
    creator_id INTEGER NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
    build_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE UNIQUE INDEX "uk_bento_bentoRepositoryId_version" ON "bento" ("bento_repository_id", "version");

CREATE TABLE IF NOT EXISTS "model_repository" (
    id SERIAL PRIMARY KEY,
    uid VARCHAR(32) UNIQUE NOT NULL DEFAULT generate_object_id(),
    name VARCHAR(128) NOT NULL,
    description TEXT,
    manifest JSONB,
    organization_id INTEGER NOT NULL REFERENCES "organization"("id") ON DELETE CASCADE,
    creator_id INTEGER NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE UNIQUE INDEX "uk_modelRepository_orgId_name" ON "model_repository" ("organization_id", "name");

CREATE TYPE "model_upload_status" AS ENUM ('pending', 'uploading', 'success', 'failed');
CREATE TYPE "model_image_build_status" AS ENUM ('pending', 'building', 'success', 'failed');

CREATE TABLE IF NOT EXISTS "model" (
    id SERIAL PRIMARY KEY,
    uid VARCHAR(32) UNIQUE NOT NULL DEFAULT generate_object_id(),
    version VARCHAR(512) NOT NULL,
    description TEXT,
    manifest JSONB,
    model_repository_id INTEGER NOT NULL REFERENCES "model_repository"("id") ON DELETE CASCADE,
    upload_status model_upload_status NOT NULL DEFAULT 'pending',
    image_build_status model_image_build_status NOT NULL DEFAULT 'pending',
    image_build_status_syncing_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    image_build_status_updated_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    upload_started_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    upload_finished_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    upload_finished_reason TEXT,
    creator_id INTEGER NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
    build_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE UNIQUE INDEX "uk_model_modelRepositoryId_version" ON "model" ("model_repository_id", "version");

CREATE TABLE IF NOT EXISTS "bento_model_rel" (
    id SERIAL PRIMARY KEY,
    bento_id INTEGER NOT NULL REFERENCES "bento"("id") ON DELETE CASCADE,
    model_id INTEGER NOT NULL REFERENCES "model"("id") ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE UNIQUE INDEX "uk_bentoModelRel_bentoId_modelId" ON "bento_model_rel" ("bento_id", "model_id");

CREATE TYPE "deployment_status" AS ENUM ('unknown', 'non-deployed', 'failed', 'unhealthy', 'deploying', 'running', 'terminating', 'terminated');

CREATE TABLE IF NOT EXISTS "deployment" (
    id SERIAL PRIMARY KEY,
    uid VARCHAR(32) UNIQUE NOT NULL DEFAULT generate_object_id(),
    name VARCHAR(128) NOT NULL,
    description TEXT,
    cluster_id INTEGER NOT NULL REFERENCES "cluster"("id") ON DELETE CASCADE,
    status deployment_status NOT NULL DEFAULT 'non-deployed',
    status_syncing_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    status_updated_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    kube_deploy_token VARCHAR(128) DEFAULT '',
    kube_namespace VARCHAR(128) NOT NULL,
    creator_id INTEGER NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE UNIQUE INDEX "uk_deployment_clusterId_name" ON "deployment" ("cluster_id", "name");

CREATE TYPE "deployment_revision_status" AS ENUM ('active', 'inactive');

CREATE TABLE IF NOT EXISTS deployment_revision (
    id SERIAL PRIMARY KEY,
    uid VARCHAR(32) UNIQUE NOT NULL DEFAULT generate_object_id(),
    status deployment_revision_status NOT NULL DEFAULT 'active',
    deployment_id INTEGER NOT NULL REFERENCES "deployment"("id") ON DELETE CASCADE,
    config TEXT DEFAULT '{}',
    creator_id INTEGER NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE TYPE "deployment_target_type" AS ENUM ('stable', 'canary');

CREATE TABLE IF NOT EXISTS "deployment_target" (
    id SERIAL PRIMARY KEY,
    uid VARCHAR(32) UNIQUE NOT NULL DEFAULT generate_object_id(),
    type deployment_target_type NOT NULL DEFAULT 'stable',
    canary_rules TEXT,
    deployment_revision_id INTEGER NOT NULL REFERENCES "deployment_revision"("id") ON DELETE CASCADE,
    deployment_id INTEGER NOT NULL REFERENCES "deployment"("id") ON DELETE CASCADE,
    bento_id INTEGER REFERENCES "bento"("id") ON DELETE CASCADE,
    config TEXT DEFAULT '{}',
    creator_id INTEGER NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE TYPE "resource_type" AS ENUM ('user', 'organization', 'cluster', 'bento_repository', 'bento', 'deployment', 'deployment_revision', 'model_repository', 'model', 'api_token');

CREATE TYPE "event_status" AS ENUM ('pending', 'success', 'failed');

CREATE TABLE IF NOT EXISTS "event" (
    id SERIAL PRIMARY KEY,
    uid VARCHAR(32) UNIQUE NOT NULL DEFAULT generate_object_id(),
    name VARCHAR(128) NOT NULL,
    status event_status NOT NULL DEFAULT 'pending',
    organization_id INTEGER REFERENCES "organization"("id") ON DELETE CASCADE,
    cluster_id INTEGER REFERENCES "cluster"("id") ON DELETE CASCADE,
    resource_type resource_type NOT NULL,
    resource_id INTEGER NOT NULL,
    operation_name VARCHAR(128) NOT NULL,
    info TEXT DEFAULT '{}',
    api_token_name VARCHAR(128) DEFAULT NULL,
    creator_id INTEGER NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS "terminal_record" (
    id SERIAL PRIMARY KEY,
    uid VARCHAR(32) UNIQUE NOT NULL DEFAULT generate_object_id(),
    organization_id INTEGER DEFAULT NULL REFERENCES "organization"("id") ON DELETE CASCADE,
    cluster_id INTEGER DEFAULT NULL REFERENCES "cluster"("id") ON DELETE CASCADE,
    deployment_id INTEGER DEFAULT NULL REFERENCES "deployment"("id") ON DELETE CASCADE,
    resource_type resource_type NOT NULL,
    resource_id INTEGER NOT NULL,
    pod_name VARCHAR(128) NOT NULL,
    container_name VARCHAR(128) NOT NULL,
    meta TEXT,
    content TEXT[],
    creator_id INTEGER NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS "cache" (
    id SERIAL PRIMARY KEY,
    key VARCHAR(512) UNIQUE NOT NULL,
    value TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS "label" (
    id SERIAL PRIMARY KEY,
    uid VARCHAR(32) UNIQUE NOT NULL DEFAULT generate_object_id(),
    resource_type resource_type NOT NULL,
    resource_id INTEGER NOT NULL,
    key VARCHAR(128) NOT NULL,
    value VARCHAR(128) NOT NULL,
    creator_id INTEGER NOT NULL REFERENCES "user"("id") ON DELETE CASCADE,
    organization_id INTEGER REFERENCES "organization"("id") ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE UNIQUE INDEX "uk_label_orgId_resourceType_resourceId_key" on "label" ("organization_id", "resource_type", "resource_id", "key");
