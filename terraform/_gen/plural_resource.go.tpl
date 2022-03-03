// Code generated by _gen/main.go DO NOT EDIT
/*
Copyright 2015-2021 Gravitational, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package provider

import (
	"context"
	"fmt"
	{{if .RandomMetadataName}}
	"crypto/rand"
	"encoding/hex"
	{{end}}

	"github.com/hashicorp/terraform-plugin-framework/diag"
	"github.com/hashicorp/terraform-plugin-framework/tfsdk"
	"github.com/hashicorp/terraform-plugin-framework/types"
	"github.com/hashicorp/terraform-plugin-go/tftypes"

	"github.com/gravitational/teleport-plugins/terraform/tfschema"
	apitypes "github.com/gravitational/teleport/api/types"
	"github.com/gravitational/trace"
)

// resourceTeleport{{.Name}}Type is the resource metadata type
type resourceTeleport{{.Name}}Type struct{}

// resourceTeleport{{.Name}} is the resource
type resourceTeleport{{.Name}} struct {
	p Provider
}

// GetSchema returns the resource schema
func (r resourceTeleport{{.Name}}Type) GetSchema(ctx context.Context) (tfsdk.Schema, diag.Diagnostics) {
	return tfschema.GenSchema{{.TypeName}}(ctx)
}

// NewResource creates the empty resource
func (r resourceTeleport{{.Name}}Type) NewResource(_ context.Context, p tfsdk.Provider) (tfsdk.Resource, diag.Diagnostics) {
	return resourceTeleport{{.Name}}{
		p: *(p.(*Provider)),
	}, nil
}

// Create creates the provision token
func (r resourceTeleport{{.Name}}) Create(ctx context.Context, req tfsdk.CreateResourceRequest, resp *tfsdk.CreateResourceResponse) {
	if !r.p.IsConfigured(resp.Diagnostics) {
		return
	}

	var plan types.Object
	diags := req.Plan.Get(ctx, &plan)
	resp.Diagnostics.Append(diags...)
	if resp.Diagnostics.HasError() {
		return
	}

	{{.VarName}} := &apitypes.{{.TypeName}}{}
	diags = tfschema.Copy{{.TypeName}}FromTerraform(ctx, plan, {{.VarName}})
	resp.Diagnostics.Append(diags...)
	if resp.Diagnostics.HasError() {
		return
	}

	{{if .RandomMetadataName -}}
	if {{.VarName}}.Metadata.Name == "" {
		b := make([]byte, 32)
		_, err := rand.Read(b)
		if err != nil {
			resp.Diagnostics.AddError("Failed to generate random token", err.Error())
			return
		}
		{{.VarName}}.Metadata.Name = hex.EncodeToString(b)
	}
	{{end -}}

	_, err := r.p.Client.{{.GetMethod}}({{if not .GetWithoutContext}}ctx, {{end}}{{.VarName}}.Metadata.Name{{if ne .WithSecrets ""}}, {{.WithSecrets}}{{end}})
	if !trace.IsNotFound(err) {
		if err == nil {
			n := {{.VarName}}.Metadata.Name
			existErr := fmt.Sprintf("{{.Name}} exists in Teleport. Either remove it (tctl rm {{.Kind}}/%v)"+
				" or import it to the existing state (terraform import teleport_app.%v %v)", n, n, n)

			resp.Diagnostics.Append(diagFromErr("{{.Name}} exists in Teleport", trace.Errorf(existErr)))
			return
		}

		resp.Diagnostics.Append(diagFromWrappedErr("Error reading {{.Name}}", trace.Wrap(err), "{{.Kind}}"))
		return
	}

	err = {{.VarName}}.CheckAndSetDefaults()
	if err != nil {
		resp.Diagnostics.Append(diagFromWrappedErr("Error setting {{.Name}} defaults", trace.Wrap(err), "{{.Kind}}"))
		return
	}

	{{if eq .UpsertMethodArity 2}}_, {{end}}err = r.p.Client.{{.CreateMethod}}(ctx, {{.VarName}})
	if err != nil {
		resp.Diagnostics.Append(diagFromWrappedErr("Error creating {{.Name}}", trace.Wrap(err), "{{.Kind}}"))
		return
	}

	id := {{.VarName}}.Metadata.Name
	{{.VarName}}I, err := r.p.Client.{{.GetMethod}}({{if not .GetWithoutContext}}ctx, {{end}}id{{if ne .WithSecrets ""}}, {{.WithSecrets}}{{end}})
	if err != nil {
		resp.Diagnostics.Append(diagFromWrappedErr("Error reading {{.Name}}", trace.Wrap(err), "{{.Kind}}"))
		return
	}

	{{.VarName}}, ok := {{.VarName}}I.(*apitypes.{{.TypeName}})
	if !ok {
		resp.Diagnostics.Append(diagFromWrappedErr("Error reading {{.Name}}", trace.Errorf("Can not convert %T to {{.TypeName}}", {{.VarName}}I), "{{.Kind}}"))
		return
	}

	diags = tfschema.Copy{{.TypeName}}ToTerraform(ctx, *{{.VarName}}, &plan)
	resp.Diagnostics.Append(diags...)
	if resp.Diagnostics.HasError() {
		return
	}

	plan.Attrs["id"] = types.String{Value: {{.ID}}}

	diags = resp.State.Set(ctx, &plan)
	resp.Diagnostics.Append(diags...)
	if resp.Diagnostics.HasError() {
		return
	}
}

// Read reads teleport {{.Name}}
func (r resourceTeleport{{.Name}}) Read(ctx context.Context, req tfsdk.ReadResourceRequest, resp *tfsdk.ReadResourceResponse) {
	var state types.Object
	diags := req.State.Get(ctx, &state)
	resp.Diagnostics.Append(diags...)
	if resp.Diagnostics.HasError() {
		return
	}

	var id types.String
	diags = req.State.GetAttribute(ctx, tftypes.NewAttributePath().WithAttributeName("metadata").WithAttributeName("name"), &id)
	resp.Diagnostics.Append(diags...)
	if resp.Diagnostics.HasError() {
		return
	}

	{{.VarName}}I, err := r.p.Client.{{.GetMethod}}({{if not .GetWithoutContext}}ctx, {{end}}id.Value{{if ne .WithSecrets ""}}, {{.WithSecrets}}{{end}})
	if err != nil {
		resp.Diagnostics.Append(diagFromWrappedErr("Error reading {{.Name}}", trace.Wrap(err), "{{.Kind}}"))
		return
	}

	{{.VarName}} := {{.VarName}}I.(*apitypes.{{.TypeName}})
	diags = tfschema.Copy{{.TypeName}}ToTerraform(ctx, *{{.VarName}}, &state)
	resp.Diagnostics.Append(diags...)
	if resp.Diagnostics.HasError() {
		return
	}

	diags = resp.State.Set(ctx, &state)
	resp.Diagnostics.Append(diags...)
	if resp.Diagnostics.HasError() {
		return
	}
}

// Update updates teleport {{.Name}}
func (r resourceTeleport{{.Name}}) Update(ctx context.Context, req tfsdk.UpdateResourceRequest, resp *tfsdk.UpdateResourceResponse) {
	if !r.p.IsConfigured(resp.Diagnostics) {
		return
	}

	var plan types.Object
	diags := req.Plan.Get(ctx, &plan)

	resp.Diagnostics.Append(diags...)
	if resp.Diagnostics.HasError() {
		return
	}

	{{.VarName}} := &apitypes.{{.TypeName}}{}
	diags = tfschema.Copy{{.TypeName}}FromTerraform(ctx, plan, {{.VarName}})
	resp.Diagnostics.Append(diags...)
	if resp.Diagnostics.HasError() {
		return
	}

	name := {{.VarName}}.Metadata.Name

	err := {{.VarName}}.CheckAndSetDefaults()
	if err != nil {
		resp.Diagnostics.Append(diagFromWrappedErr("Error updating {{.Name}}", err, "{{.Kind}}"))
		return
	}

	{{if eq .UpsertMethodArity 2}}_, {{end}}err = r.p.Client.{{.UpdateMethod}}(ctx, {{.VarName}})
	if err != nil {
		resp.Diagnostics.Append(diagFromWrappedErr("Error updating {{.Name}}", err, "{{.Kind}}"))
		return
	}

	{{.VarName}}I, err := r.p.Client.{{.GetMethod}}({{if not .GetWithoutContext}}ctx, {{end}}name{{if ne .WithSecrets ""}}, {{.WithSecrets}}{{end}})
	if err != nil {
		resp.Diagnostics.Append(diagFromWrappedErr("Error reading {{.Name}}", err, "{{.Kind}}"))
		return
	}

	{{.VarName}} = {{.VarName}}I.(*apitypes.{{.TypeName}})
	diags = tfschema.Copy{{.TypeName}}ToTerraform(ctx, *{{.VarName}}, &plan)
	resp.Diagnostics.Append(diags...)
	if resp.Diagnostics.HasError() {
		return
	}

	diags = resp.State.Set(ctx, plan)
	resp.Diagnostics.Append(diags...)
	if resp.Diagnostics.HasError() {
		return
	}
}

// Delete deletes Teleport {{.Name}}
func (r resourceTeleport{{.Name}}) Delete(ctx context.Context, req tfsdk.DeleteResourceRequest, resp *tfsdk.DeleteResourceResponse) {
	var id types.String
	diags := req.State.GetAttribute(ctx, tftypes.NewAttributePath().WithAttributeName("metadata").WithAttributeName("name"), &id)
	resp.Diagnostics.Append(diags...)
	if resp.Diagnostics.HasError() {
		return
	}

	err := r.p.Client.{{.DeleteMethod}}(ctx, id.Value)
	if err != nil {
		resp.Diagnostics.Append(diagFromWrappedErr("Error deleting {{.TypeName}}", trace.Wrap(err), "{{.Kind}}"))
		return
	}

	resp.State.RemoveResource(ctx)
}

// ImportState imports {{.Name}} state
func (r resourceTeleport{{.Name}}) ImportState(ctx context.Context, req tfsdk.ImportResourceStateRequest, resp *tfsdk.ImportResourceStateResponse) {
	{{.VarName}}I, err := r.p.Client.{{.GetMethod}}({{if not .GetWithoutContext}}ctx, {{end}}req.ID{{if ne .WithSecrets ""}}, {{.WithSecrets}}{{end}})
	if err != nil {
		resp.Diagnostics.Append(diagFromWrappedErr("Error reading {{.Name}}", trace.Wrap(err), "{{.Kind}}"))
		return
	}

	{{.VarName}} := {{.VarName}}I.(*apitypes.{{.TypeName}})

	var state types.Object

	diags := resp.State.Get(ctx, &state)
	resp.Diagnostics.Append(diags...)
	if resp.Diagnostics.HasError() {
		return
	}

	diags = tfschema.Copy{{.TypeName}}ToTerraform(ctx, *{{.VarName}}, &state)
	resp.Diagnostics.Append(diags...)
	if resp.Diagnostics.HasError() {
		return
	}

	state.Attrs["id"] = types.String{Value: {{.VarName}}.Metadata.Name}

	diags = resp.State.Set(ctx, &state)
	resp.Diagnostics.Append(diags...)
	if resp.Diagnostics.HasError() {
		return
	}
}
