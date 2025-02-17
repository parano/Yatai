package transformersv1

import (
	"context"

	"github.com/pkg/errors"

	"github.com/bentoml/yatai/api-server/models"
	"github.com/bentoml/yatai/schemas/schemasv1"
)

func ToLabelSchema(ctx context.Context, label *models.Label) (*schemasv1.LabelSchema, error) {
	if label == nil {
		return nil, nil
	}
	ss, err := ToLabelSchemas(ctx, []*models.Label{label})
	if err != nil {
		return nil, errors.Wrap(err, "ToLabelSchema")
	}
	return ss[0], nil
}

func ToLabelSchemas(ctx context.Context, labels []*models.Label) ([]*schemasv1.LabelSchema, error) {
	// NOTE: value, err := LabelService.ListLabelValuesByKey
	resourceSchemasMap, err := ToResourceSchemasMap(ctx, labels)
	if err != nil {
		return nil, errors.Wrap(err, "ToLabelSchemas")
	}
	ss := make([]*schemasv1.LabelSchema, 0, len(labels))
	for _, r := range labels {
		creatorSchema, err := GetAssociatedCreatorSchema(ctx, r)
		if err != nil {
			return nil, err
		}
		orgSchema, err := GetAssociatedOrganizationSchema(ctx, r)
		if err != nil {
			return nil, err
		}
		resourceSchema, ok := resourceSchemasMap[r.GetUid()]
		if !ok {
			return nil, errors.Errorf("ToLabelSchemas: resource schema not found for label %s", r.GetUid())
		}

		ss = append(ss, &schemasv1.LabelSchema{
			ResourceSchema: resourceSchema,
			Organization:   orgSchema,
			Creator:        creatorSchema,
			ResourceType:   r.ResourceType,
			ResourceUid:    r.GetUid(),
			Key:            r.Key,
			Value:          r.Value, // NOTE (refers above): KeyValueMap[r.getValue()]
		})
	}

	return ss, nil
}
