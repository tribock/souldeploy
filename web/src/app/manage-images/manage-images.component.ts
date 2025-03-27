import { Component, OnInit } from '@angular/core';
import { ApiService } from '../api.service';
import { FormBuilder, FormGroup, Validators } from '@angular/forms';

import { HttpEventType, HttpResponse } from '@angular/common/http';
import { Observable } from 'rxjs';

@Component({
    selector: 'app-manage-images',
    templateUrl: './manage-images.component.html',
    styleUrls: ['./manage-images.component.scss'],
    standalone: false
})
export class ManageImagesComponent implements OnInit {
  images;

  //file upload
  selectedFiles?: FileList;
  hash: string;
  description: string;
  currentFile?: File;
  progress = 0;
  message = '';
  fileInfos?: Observable<any>;

  constructor(private apiService: ApiService) {

  }

  ngOnInit(): void {
    this.apiService.getImages().subscribe((images: any) => {
      this.images = images;
    });
  }

  selectFile(event: any): void {
    this.selectedFiles = event.target.files;
  }

  upload(): void {
    this.progress = 0;
    if (this.selectedFiles) {
      const file: File | null = this.selectedFiles.item(0);

      if (file) {
        this.currentFile = file;

        this.apiService.addImage(this.currentFile, this.hash, this.description).subscribe(
          (event: any) => {
            if (event.type === HttpEventType.UploadProgress) {
              this.progress = Math.round(100 * event.loaded / event.total);
            } else if (event instanceof HttpResponse) {
              this.message = event.body.message;
              this.images.push(event.body);
            }
          },
          (err: any) => {
            this.progress = 0;

            this.message = err?.error?.message || err?.error?.error_message || 'Could not upload the file!';

            this.currentFile = undefined;
          });
      }

      this.selectedFiles = undefined;
    }
  }

  remove(id) {
    this.apiService.deleteImage(id).subscribe((data: any) => {
      this.images = this.images.filter(item => item.id !== id);
    }, (data: any) => {
      if (data.error) {
        this.message = data.error;
      }
    });
  }

}
